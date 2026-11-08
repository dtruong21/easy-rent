import type * as admin from "firebase-admin";
import type Stripe from "stripe";
import {beforeEach, describe, expect, it, vi} from "vitest";

import {
  ensureStripeCustomer,
  expireOpenCheckoutSessions,
  isStripeResourceMissing,
  listSubscriptionsForUid,
  readStripeCustomerId,
} from "../utils/stripe_customer";

import {FakeFirestore} from "./helpers/fake_firestore";

vi.mock("firebase-admin", async () => {
  const {makeFakeAdminModule} = await import("./helpers/fake_firestore");
  return makeFakeAdminModule();
});
vi.mock("firebase-admin/firestore", async () => {
  const {fakeFieldValue, fakeTimestamp} = await import(
    "./helpers/fake_firestore"
  );
  return {FieldValue: fakeFieldValue, Timestamp: fakeTimestamp};
});

const UID = "landlord-a";

const fake = {
  customersCreate: vi.fn(),
  customersUpdate: vi.fn(),
  customersDel: vi.fn(),
  list: vi.fn(),
  search: vi.fn(),
  sessionsList: vi.fn(),
  sessionsExpire: vi.fn(),
  sessionsRetrieve: vi.fn(),
};
const stripe = {
  customers: {
    create: fake.customersCreate,
    update: fake.customersUpdate,
    del: fake.customersDel,
  },
  subscriptions: {list: fake.list, search: fake.search},
  checkout: {
    sessions: {
      list: fake.sessionsList,
      expire: fake.sessionsExpire,
      retrieve: fake.sessionsRetrieve,
    },
  },
} as unknown as Stripe;

let fakeDb: FakeFirestore;
const db = (): admin.firestore.Firestore =>
  fakeDb as unknown as admin.firestore.Firestore;

const missing = (param?: string): object =>
  Object.assign(new Error("No such object"), {code: "resource_missing", param});

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fake.customersCreate.mockReset().mockResolvedValue({id: "cus_new"});
  fake.customersUpdate.mockReset().mockResolvedValue({});
  fake.customersDel.mockReset().mockResolvedValue({});
  fake.sessionsList.mockReset().mockResolvedValue({data: [], has_more: false});
  fake.sessionsExpire.mockReset().mockResolvedValue({});
  fake.sessionsRetrieve.mockReset().mockRejectedValue(new Error("not stubbed"));
  fake.list.mockReset().mockResolvedValue({data: [], has_more: false});
  fake.search.mockReset().mockResolvedValue({data: [], has_more: false});
});

describe("readStripeCustomerId", () => {
  it("aucun doc → null", async () => {
    expect(await readStripeCustomerId(db(), UID)).toBeNull();
  });

  it("doc enregistré → son identifiant", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_1"});
    expect(await readStripeCustomerId(db(), UID)).toBe("cus_1");
  });

  it("valeur atypique (vide, non-chaîne) → null, jamais d'exception", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: ""});
    expect(await readStripeCustomerId(db(), UID)).toBeNull();
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: 42});
    expect(await readStripeCustomerId(db(), UID)).toBeNull();
  });

  it("ne lit que le doc de CE compte", async () => {
    fakeDb.seed("stripe_customers/landlord-b", {customerId: "cus_b"});
    expect(await readStripeCustomerId(db(), UID)).toBeNull();
  });
});

describe("isStripeResourceMissing", () => {
  it("reconnaît le code resource_missing", () => {
    expect(isStripeResourceMissing(missing())).toBe(true);
    expect(isStripeResourceMissing({code: "card_declined"})).toBe(false);
    expect(isStripeResourceMissing(null)).toBe(false);
    expect(isStripeResourceMissing("resource_missing")).toBe(false);
  });

  it("avec un paramètre : exige que l'erreur porte sur CE paramètre", () => {
    expect(isStripeResourceMissing(missing("customer"), "customer")).toBe(true);
    // Un price mal configuré n'est pas un client supprimé.
    expect(
      isStripeResourceMissing(missing("line_items[0][price]"), "customer"),
    ).toBe(false);
    expect(isStripeResourceMissing(missing(), "customer")).toBe(false);
  });
});

describe("ensureStripeCustomer", () => {
  it("première ouverture → crée le client (email + uid en metadata) et l'enregistre", async () => {
    const id = await ensureStripeCustomer({
      db: db(),
      stripe,
      uid: UID,
      email: "a@example.test",
    });

    expect(id).toBe("cus_new");
    expect(fake.customersCreate).toHaveBeenCalledWith({
      email: "a@example.test",
      metadata: {rc_app_user_id: UID},
    });
    expect(fakeDb.peek(`stripe_customers/${UID}`)).toMatchObject({
      customerId: "cus_new",
    });
  });

  it("sans email → client créé sans champ email", async () => {
    await ensureStripeCustomer({db: db(), stripe, uid: UID, email: null});
    expect(fake.customersCreate).toHaveBeenCalledWith({
      metadata: {rc_app_user_id: UID},
    });
  });

  it("client déjà enregistré → réutilisé, AUCUNE création", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_1"});

    const id = await ensureStripeCustomer({
      db: db(),
      stripe,
      uid: UID,
      email: "a@example.test",
    });

    expect(id).toBe("cus_1");
    expect(fake.customersCreate).not.toHaveBeenCalled();
    // Email du compte reporté sur le client : les reçus suivent l'adresse courante.
    expect(fake.customersUpdate).toHaveBeenCalledWith("cus_1", {
      email: "a@example.test",
    });
  });

  it("mise à jour de l'email en échec → n'empêche pas de réutiliser le client", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_1"});
    fake.customersUpdate.mockRejectedValue(new Error("stripe hiccup"));

    expect(
      await ensureStripeCustomer({
        db: db(),
        stripe,
        uid: UID,
        email: "a@example.test",
      }),
    ).toBe("cus_1");
  });

  it("compte sans email → aucune mise à jour du client réutilisé", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_1"});

    await ensureStripeCustomer({db: db(), stripe, uid: UID, email: null});

    expect(fake.customersUpdate).not.toHaveBeenCalled();
  });

  it("identifiant périmé déjà remplacé par un autre appel → le nouveau est réutilisé, aucune création", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_replaced"});

    const id = await ensureStripeCustomer({
      db: db(),
      stripe,
      uid: UID,
      email: null,
      staleCustomerId: "cus_gone",
    });

    expect(id).toBe("cus_replaced");
    expect(fake.customersCreate).not.toHaveBeenCalled();
  });

  it("identifiant périmé (client supprimé chez Stripe) → remplacé par un client neuf", async () => {
    fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_gone"});

    const id = await ensureStripeCustomer({
      db: db(),
      stripe,
      uid: UID,
      email: null,
      staleCustomerId: "cus_gone",
    });

    expect(id).toBe("cus_new");
    expect(fakeDb.peek(`stripe_customers/${UID}`)).toMatchObject({
      customerId: "cus_new",
    });
  });

  it("ouverture concurrente : le client déjà enregistré gagne, pas le nôtre", async () => {
    // L'autre appel enregistre son client pendant notre création Stripe.
    fake.customersCreate.mockImplementation(() => {
      fakeDb.seed(`stripe_customers/${UID}`, {customerId: "cus_other"});
      return Promise.resolve({id: "cus_new"});
    });

    const id = await ensureStripeCustomer({
      db: db(),
      stripe,
      uid: UID,
      email: null,
    });

    expect(id).toBe("cus_other");
    expect(fakeDb.peek(`stripe_customers/${UID}`)).toMatchObject({
      customerId: "cus_other",
    });
    // Le client créé en trop porte l'email : il est supprimé chez Stripe.
    expect(fake.customersDel).toHaveBeenCalledWith("cus_new");
  });

  it("client enregistré normalement → jamais supprimé", async () => {
    await ensureStripeCustomer({db: db(), stripe, uid: UID, email: null});
    expect(fake.customersDel).not.toHaveBeenCalled();
  });

  it("création Stripe en échec → rien d'enregistré, erreur propagée", async () => {
    fake.customersCreate.mockRejectedValue(new Error("stripe down"));

    await expect(
      ensureStripeCustomer({db: db(), stripe, uid: UID, email: null}),
    ).rejects.toThrow("stripe down");
    expect(fakeDb.peek(`stripe_customers/${UID}`)).toBeUndefined();
  });
});

describe("listSubscriptionsForUid", () => {
  const sub = (id: string): {id: string} => ({id});
  const ids = (subs: {id: string}[]): string[] => subs.map((s) => s.id);

  it("sans client enregistré → recherche par metadata seule", async () => {
    fake.search.mockResolvedValue({data: [sub("sub_1")]});

    expect(ids(await listSubscriptionsForUid(stripe, UID, null))).toEqual([
      "sub_1",
    ]);
    expect(fake.list).not.toHaveBeenCalled();
    expect(fake.search).toHaveBeenCalledWith({
      query: `metadata['rc_app_user_id']:'${UID}'`,
      limit: 100,
    });
  });

  it("★ abonnement tout juste payé, encore invisible de la recherche → trouvé par le client", async () => {
    fake.list.mockResolvedValue({data: [sub("sub_fresh")], has_more: false});
    fake.search.mockResolvedValue({data: []});

    expect(ids(await listSubscriptionsForUid(stripe, UID, "cus_1"))).toEqual([
      "sub_fresh",
    ]);
    expect(fake.list).toHaveBeenCalledWith({
      customer: "cus_1",
      status: "all",
      limit: 100,
    });
  });

  it("les deux sources sont réunies et dédoublonnées", async () => {
    fake.list.mockResolvedValue({data: [sub("sub_a"), sub("sub_b")]});
    fake.search.mockResolvedValue({data: [sub("sub_b"), sub("sub_legacy")]});

    expect(ids(await listSubscriptionsForUid(stripe, UID, "cus_1"))).toEqual([
      "sub_a",
      "sub_b",
      "sub_legacy",
    ]);
  });

  // Sans cela : résilier, réactiver, puis résilier dans la minute rendait
  // « déjà programmé » (copie périmée de la recherche) et Stripe renouvelait.
  it("★ même abonnement dans les deux sources → la version de la liste fait foi", async () => {
    fake.list.mockResolvedValue({
      data: [{id: "sub_1", cancel_at_period_end: false}],
    });
    fake.search.mockResolvedValue({
      data: [{id: "sub_1", cancel_at_period_end: true}],
    });

    const subs = await listSubscriptionsForUid(stripe, UID, "cus_1");

    expect(subs).toEqual([{id: "sub_1", cancel_at_period_end: false}]);
  });

  it("curseur de pagination introuvable → propagé (jamais une liste partielle)", async () => {
    fake.list.mockRejectedValue(missing("starting_after"));

    await expect(
      listSubscriptionsForUid(stripe, UID, "cus_1"),
    ).rejects.toMatchObject({code: "resource_missing"});
  });

  it("liste par client paginée jusqu'au bout (starting_after)", async () => {
    fake.list
      .mockResolvedValueOnce({data: [sub("sub_1"), sub("sub_2")], has_more: true})
      .mockResolvedValueOnce({data: [sub("sub_3")], has_more: false});

    expect(ids(await listSubscriptionsForUid(stripe, UID, "cus_1"))).toEqual([
      "sub_1",
      "sub_2",
      "sub_3",
    ]);
    expect(fake.list).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({starting_after: "sub_2"}),
    );
  });

  it("recherche paginée jusqu'au bout (next_page)", async () => {
    fake.search
      .mockResolvedValueOnce({
        data: [sub("sub_1")],
        has_more: true,
        next_page: "tok_2",
      })
      .mockResolvedValueOnce({data: [sub("sub_2")], has_more: false});

    expect(ids(await listSubscriptionsForUid(stripe, UID, null))).toEqual([
      "sub_1",
      "sub_2",
    ]);
    expect(fake.search).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({page: "tok_2"}),
    );
  });

  it("client supprimé chez Stripe → ignoré, la recherche fait foi", async () => {
    fake.list.mockRejectedValue(missing("customer"));
    fake.search.mockResolvedValue({data: [sub("sub_legacy")]});

    expect(ids(await listSubscriptionsForUid(stripe, UID, "cus_gone"))).toEqual([
      "sub_legacy",
    ]);
  });

  it("autre erreur sur la liste par client → propagée (jamais un faux « aucun abonnement »)", async () => {
    fake.list.mockRejectedValue(new Error("stripe down"));

    await expect(listSubscriptionsForUid(stripe, UID, "cus_1")).rejects.toThrow(
      "stripe down",
    );
  });

  it("recherche en échec → propagée, même si la liste par client a répondu", async () => {
    fake.list.mockResolvedValue({data: [sub("sub_a")]});
    fake.search.mockRejectedValue(new Error("search down"));

    await expect(listSubscriptionsForUid(stripe, UID, "cus_1")).rejects.toThrow(
      "search down",
    );
  });

  it("uid malformé → invalid-argument, AUCUN appel Stripe", async () => {
    await expect(
      listSubscriptionsForUid(stripe, "x' OR status:'active", "cus_1"),
    ).rejects.toMatchObject({code: "invalid-argument"});
    expect(fake.list).not.toHaveBeenCalled();
    expect(fake.search).not.toHaveBeenCalled();
  });
});

describe("expireOpenCheckoutSessions", () => {
  it("ferme chaque session encore ouverte du client", async () => {
    fake.sessionsList.mockResolvedValue({
      data: [{id: "cs_1"}, {id: "cs_2"}],
      has_more: false,
    });

    await expireOpenCheckoutSessions(stripe, "cus_1");

    expect(fake.sessionsList).toHaveBeenCalledWith({
      customer: "cus_1",
      status: "open",
      limit: 100,
    });
    expect(fake.sessionsExpire.mock.calls).toEqual([["cs_1"], ["cs_2"]]);
  });

  it("aucune session ouverte → aucun appel", async () => {
    await expireOpenCheckoutSessions(stripe, "cus_1");
    expect(fake.sessionsExpire).not.toHaveBeenCalled();
  });

  it("plus de 100 sessions → relit jusqu'à épuisement", async () => {
    fake.sessionsList
      .mockResolvedValueOnce({data: [{id: "cs_1"}], has_more: true})
      .mockResolvedValueOnce({data: [{id: "cs_2"}], has_more: false});

    await expireOpenCheckoutSessions(stripe, "cus_1");

    expect(fake.sessionsExpire.mock.calls).toEqual([["cs_1"], ["cs_2"]]);
  });

  it("page vide annoncée « à suivre » → s'arrête (jamais de boucle sans fin)", async () => {
    fake.sessionsList.mockResolvedValueOnce({data: [], has_more: true});

    await expireOpenCheckoutSessions(stripe, "cus_1");

    expect(fake.sessionsList).toHaveBeenCalledOnce();
  });

  it("client supprimé chez Stripe → rien à fermer, pas d'erreur", async () => {
    fake.sessionsList.mockRejectedValue(missing("customer"));

    await expect(
      expireOpenCheckoutSessions(stripe, "cus_gone"),
    ).resolves.toBeUndefined();
  });

  it("liste en échec → propagée", async () => {
    fake.sessionsList.mockRejectedValue(new Error("stripe down"));

    await expect(expireOpenCheckoutSessions(stripe, "cus_1")).rejects.toThrow(
      "stripe down",
    );
  });

  it("fermeture en échec mais session payée entre-temps → toléré", async () => {
    fake.sessionsList.mockResolvedValue({data: [{id: "cs_1"}], has_more: false});
    fake.sessionsExpire.mockRejectedValue(new Error("not open"));
    fake.sessionsRetrieve.mockResolvedValue({id: "cs_1", status: "complete"});

    await expect(
      expireOpenCheckoutSessions(stripe, "cus_1"),
    ).resolves.toBeUndefined();
  });

  it("fermeture en échec et session TOUJOURS ouverte → propagée", async () => {
    fake.sessionsList.mockResolvedValue({data: [{id: "cs_1"}], has_more: false});
    fake.sessionsExpire.mockRejectedValue(new Error("stripe down"));
    fake.sessionsRetrieve.mockResolvedValue({id: "cs_1", status: "open"});

    await expect(expireOpenCheckoutSessions(stripe, "cus_1")).rejects.toThrow(
      "stripe down",
    );
  });

  it("fermeture en échec et relecture impossible → propagée (dans le doute)", async () => {
    fake.sessionsList.mockResolvedValue({data: [{id: "cs_1"}], has_more: false});
    fake.sessionsExpire.mockRejectedValue(new Error("stripe down"));

    await expect(expireOpenCheckoutSessions(stripe, "cus_1")).rejects.toThrow(
      "stripe down",
    );
  });
});

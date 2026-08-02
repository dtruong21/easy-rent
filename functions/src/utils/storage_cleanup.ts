/**
 * Nettoyage des objets Storage — côté SERVEUR uniquement.
 *
 * **Pourquoi ça doit vivre ici et pas côté client** : `storage.rules` pose
 * `allow update, delete: if false` sur `documents/{landlordId}/**`. Un
 * `FirebaseStorage.instance.ref(path).delete()` depuis l'app est donc TOUJOURS
 * refusé. Tant que le nettoyage vivait dans `documents_repository.dart`, il
 * échouait silencieusement (catch + log) et chaque document supprimé laissait
 * son fichier dans le bucket : coût facturé indéfiniment, et surtout trou RGPD
 * sur le droit à l'effacement (le doc Firestore disparaît, le PDF reste).
 *
 * L'Admin SDK outrepasse les Storage Rules — c'est le seul chemin qui marche.
 */

import * as admin from "firebase-admin";
import {logger} from "firebase-functions/v2";

/**
 * Supprime un objet Storage. Best-effort et **idempotent** (`ignoreNotFound`) :
 * un objet déjà absent compte comme un succès, ce qui rend l'appel rejouable
 * sans effet de bord.
 *
 * Ne throw JAMAIS : les appelants sont soit après un commit Firestore (rendre
 * une erreur ferait croire à tort que la suppression a échoué), soit déjà en
 * train de propager une autre erreur. Les échecs sont logués en ERROR avec le
 * tag grepable `[orphan-document]` pour rattraper le résidu (cf.
 * `scripts/purge-orphan-documents.mjs`).
 *
 * @param storagePath chemin complet dans le bucket, p.ex.
 *   `documents/{uid}/{docId}.pdf`. L'appelant DOIT avoir vérifié qu'il
 *   appartient bien à l'utilisateur courant (préfixe `documents/{uid}/`).
 * @returns true si l'objet est réputé absent du bucket après l'appel.
 */
export async function deleteStorageObject(
  storagePath: string,
  uid: string,
): Promise<boolean> {
  try {
    await admin
      .storage()
      .bucket()
      .file(storagePath)
      .delete({ignoreNotFound: true});
    return true;
  } catch (err) {
    logger.error("[orphan-document] storage delete failed", {
      uid,
      storagePath,
      err,
    });
    return false;
  }
}

// site/src/lib/jsonld.ts
//
// Sérialise un objet JSON-LD pour un <script type="application/ld+json">
// (seul <script> autorisé sur la vitrine, cf. README). `<` est échappé en
// < : un contenu contenant « </script » ne peut ainsi jamais refermer la
// balise et injecter du HTML — le JSON reste strictement équivalent.
export function jsonLdString(data: unknown): string {
  return JSON.stringify(data).replace(/</g, '\\u003c');
}

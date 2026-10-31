// Head metadata shape shared by the hand-maintained routes
// (src/data/pages.ts) and the generated tool routes (src/data/tools.ts).
// Kept in its own module so tools.ts can import the type without creating
// a runtime import cycle with pages.ts.

export interface PageMeta {
  route: string;
  title: string;
  description: string;
  robots: string;
  ogType: string;
  ogImage: string;
  ogWidth: string;
  ogHeight: string;
  ogUrl: string;
  canonical: string;
  fontPreload: string | null;
  extraScripts: string[];
  headTail: string;
  contentFile: string;
}

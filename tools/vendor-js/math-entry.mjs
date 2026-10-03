import { mathjax } from "@mathjax/src/mjs/mathjax.js";
import { TeX } from "@mathjax/src/mjs/input/tex.js";
import { SVG } from "@mathjax/src/mjs/output/svg.js";
import { MathJaxTexFont } from "@mathjax/mathjax-tex-font/mjs/svg.js";
import { liteAdaptor } from "@mathjax/src/mjs/adaptors/liteAdaptor.js";
import { RegisterHTMLHandler } from "@mathjax/src/mjs/handlers/html.js";
import "@mathjax/src/mjs/input/tex/base/BaseConfiguration.js";
import "@mathjax/src/mjs/input/tex/ams/AmsConfiguration.js";
const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const doc = mathjax.document("", {
  InputJax: new TeX({ packages: ["base", "ams"], maxBuffer: 4096, maxMacros: 256 }),
  OutputJax: new SVG({ fontCache: "none", fontData: MathJaxTexFont }),
});
export function texToSvg(source, display) {
  return adaptor.outerHTML(adaptor.firstChild(doc.convert(source, { display, em: 16, ex: 8, containerWidth: 800 })));
}

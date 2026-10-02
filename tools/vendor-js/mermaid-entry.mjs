import { renderMermaidSVG } from "beautiful-mermaid";
export function mermaidToSvg(source, bg, fg) {
  return renderMermaidSVG(source, { bg, fg });
}

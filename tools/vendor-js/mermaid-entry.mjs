import { renderMermaidSVG } from "beautiful-mermaid";
export function mermaidToSvg(source, bg, fg, options = {}) {
  return renderMermaidSVG(source, { ...options, bg, fg });
}

// A small label naming the React idea a part of the page demonstrates. Reads the shared context.
import { useShowConcepts } from '../ConceptContext';

export default function ConceptTag({ children }) {
  const show = useShowConcepts();
  if (!show) return null;
  return <span className="concept">{children}</span>;
}

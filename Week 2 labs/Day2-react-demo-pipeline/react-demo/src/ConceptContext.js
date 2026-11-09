// useContext: one value (show the concept labels or not) shared by every component without passing props down.
import { createContext, useContext } from 'react';

export const ConceptContext = createContext(true);
export const useShowConcepts = () => useContext(ConceptContext);

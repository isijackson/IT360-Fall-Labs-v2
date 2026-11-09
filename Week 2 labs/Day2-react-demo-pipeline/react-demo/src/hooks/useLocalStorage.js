// Custom hook: works like useState, but the value survives a page reload because it is saved in localStorage.
import { useEffect, useState } from 'react';

export default function useLocalStorage(key, initialValue) {
  const [value, setValue] = useState(() => {
    const saved = window.localStorage.getItem(key);
    return saved !== null ? JSON.parse(saved) : initialValue;
  });
  useEffect(() => {
    if (value === null) window.localStorage.removeItem(key);
    else window.localStorage.setItem(key, JSON.stringify(value));
  }, [key, value]);
  return [value, setValue];
}

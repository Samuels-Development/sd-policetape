import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import './ui.css';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { inGame } from './nui';

createRoot(document.getElementById('root')!).render(<App />);

// In a plain browser, play the game's part so the pages can be looked at (npm run dev).
if (import.meta.env.DEV && !inGame) void import('./dev').then((m) => m.start());

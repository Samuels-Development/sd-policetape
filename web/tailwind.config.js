// The interface uses the sd-bombs admin panel's tokens (src/ui/ui.css): near-black neutral
// surfaces, hairline borders, Inter. Tailwind only names them; the values live in the CSS.
export default {
  content: { relative: true, files: ['./ui.html', './src/ui/**/*.{ts,tsx}'] },
  theme: {
    extend: {
      colors: {
        bg: 'var(--bg)',
        surface: 'var(--surface)',
        surface2: 'var(--surface-2)',
        surface3: 'var(--surface-3)',
        field: 'var(--field)',
        t1: 'var(--text-1)',
        t2: 'var(--text-2)',
        t3: 'var(--text-3)',
        t4: 'var(--text-4)',
        hairline: 'var(--hairline)',
        ok: 'var(--ok)',
        warn: 'var(--warn)',
        danger: 'var(--danger)',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'Segoe UI', 'sans-serif'],
      },
    },
  },
  plugins: [],
};

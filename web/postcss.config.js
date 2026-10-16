// Tailwind only. No autoprefixer on purpose: it drops -webkit- prefixes it thinks are stale, and
// those are the ones FiveM's Chromium 103 still needs.
export default {
  plugins: {
    tailwindcss: {},
  },
};

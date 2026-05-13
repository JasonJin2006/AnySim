/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './hooks/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        main: 'var(--text-main)',
        muted: 'var(--text-muted)',
        faint: 'var(--text-faint)',
        border: 'var(--line-soft)',
        accent: {
          200: '#f0c6ac',
          300: '#e5b36e',
          400: '#df7e53',
          500: '#d46d42',
        },
        cool: {
          300: '#b5dde0',
          400: '#99d0d3',
          500: '#6fb2b6',
        },
      },
      fontFamily: {
        sans: ['"IBM Plex Sans"', 'system-ui', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'monospace'],
      },
    },
  },
  plugins: [],
}

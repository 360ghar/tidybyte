/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./site/**/*.{html,js}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        accent: {
          DEFAULT: '#0A84FF',
          light: '#007AFF',
          dark: '#0A84FF',
        },
        brand: {
          photo: '#0A84FF',
          video: '#AF52DE',
          screenshot: '#FFCC00',
          live: '#30B0C7',
          other: '#8E8E93',
        },
      },
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"SF Pro Display"',
          '"SF Pro Text"',
          'Inter',
          'system-ui',
          'sans-serif',
        ],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      maxWidth: {
        prose: '70ch',
        content: '1120px',
      },
      boxShadow: {
        glass: '0 1px 0 0 rgba(255,255,255,0.06) inset, 0 8px 24px -8px rgba(0,0,0,0.4)',
        card: '0 4px 16px -4px rgba(0,0,0,0.25)',
      },
      backgroundImage: {
        'hero-glow':
          'radial-gradient(ellipse 80% 50% at 50% -20%, rgba(10,132,255,0.25), transparent 70%)',
        'card-glass':
          'linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0.02))',
      },
    },
  },
  plugins: [],
}

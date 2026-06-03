/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html', './src/**/*.{ts,html}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'system-ui', 'Segoe UI', 'Arial', 'sans-serif'],
      },
      colors: {
        panel: '#111113',
        surface: '#18181b',
        line: '#2f2f35',
      },
    },
  },
  plugins: [],
};

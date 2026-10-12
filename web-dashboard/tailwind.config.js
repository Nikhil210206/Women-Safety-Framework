const plugin = require('tailwindcss/plugin')

/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: "class",
  content: [
    "./app/**/*.{js,ts,jsx,tsx}",
    "./pages/**/*.{js,ts,jsx,tsx}",
    "./components/**/*.{js,ts,jsx,tsx}",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        display: ['var(--font-display)', 'Outfit', 'system-ui', 'sans-serif'],
        serif: ['var(--font-serif)', 'Georgia', 'serif'],
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
        mono: ['var(--font-mono)', 'ui-monospace', 'monospace'],
      },
      borderRadius: {
        field: '18px',
        card: '24px',
      },
      colors: {
        // WSF colour roles (values in src/app/globals.css)
        ground: 'var(--ground)',
        'ground-2': 'var(--ground-2)',
        'ground-3': 'var(--ground-3)',
        rule: 'var(--line)',
        fg: 'var(--text)',
        dim: 'var(--text-dim)',
        accent: 'var(--accent)',
        'on-accent': 'var(--on-accent)',
        block: 'var(--block)',
        'on-block': 'var(--on-block)',
        'on-block-dim': 'var(--on-block-dim)',
        inverse: 'var(--inverse)',
        'on-inverse': 'var(--on-inverse)',
        'on-danger': 'var(--on-danger)',
        caution: 'var(--caution)',
        'on-caution': 'var(--on-caution)',
        positive: 'var(--positive)',
        brand: "rgb(var(--color-brand) / <alpha-value>)",
        void: "rgb(var(--color-void) / <alpha-value>)",
        glass: "rgb(var(--color-glass) / <alpha-value>)",
        surface: "rgb(var(--color-surface) / <alpha-value>)",
        edge: "rgb(var(--color-edge) / <alpha-value>)",
        electric: "rgb(var(--color-electric) / <alpha-value>)",
        success: "rgb(var(--color-success) / <alpha-value>)",
        safe: "rgb(var(--color-safe) / <alpha-value>)",
        amber: "rgb(var(--color-amber) / <alpha-value>)",
        critical: "rgb(var(--color-critical) / <alpha-value>)",
        danger: 'var(--danger)',
        canvas: "rgb(var(--color-canvas) / <alpha-value>)",
      },
      boxShadow: {
        neon: "0 0 24px rgba(0,240,255,0.35)",
        danger: "0 0 24px rgba(255,7,58,0.35)",
        glass: "0 12px 40px rgba(0,0,0,0.32)",
        'inner-glass': 'inset 0 1px 0 0 rgba(255,255,255,0.1)',
        'radar': '0 0 0 0 rgba(255,7,58,0.6), 0 0 0 20px rgba(255,7,58,0)',
      },
      animation: {
        "ping-rapid": "ping 1s cubic-bezier(0,0,0.2,1) infinite",
        "pulse-glow": "pulse-glow 2s ease-in-out infinite",
        "radar-ping": "radar-ping 2s cubic-bezier(0,0,0.2,1) infinite",
        "slide-spring": "slide-spring 0.5s cubic-bezier(0.32,0.72,0,1)",
      },
      keyframes: {
        "pulse-glow": {
          "0%, 100%": { boxShadow: "0 0 10px rgba(0,240,255,0.3)", opacity: "1" },
          "50%": { boxShadow: "0 0 30px rgba(0,240,255,0.6)", opacity: "0.85" },
        },
        "radar-ping": {
          "0%": { transform: "scale(1)", opacity: "0.6" },
          "100%": { transform: "scale(4)", opacity: "0" },
        },
        "slide-spring": {
          "0%": { transform: "translateX(100%)", opacity: "0" },
          "60%": { transform: "translateX(-5%)", opacity: "1" },
          "100%": { transform: "translateX(0%)", opacity: "1" },
        },
      },
    },
  },
  plugins: [
    plugin(function ({ addBase, theme }) {
      addBase({
        ':root': {
          '--color-brand': '0 240 255',
          '--color-void': '240 248 255',
          '--color-glass': '229 231 235',
          '--color-surface': '209 213 219',
          '--color-edge': '156 163 175',
          '--color-electric': '14 165 233',
          '--color-success': '22 163 74',
          '--color-safe': '52 211 153',
          '--color-amber': '245 158 11',
          '--color-critical': '220 38 38',
          '--color-danger': '239 68 68',
          '--color-canvas': '241 245 249',
        },
        '.dark': {
          '--color-brand': '0 240 255',
          '--color-void': '5 10 14',
          '--color-glass': '13 31 23',
          '--color-surface': '26 38 52',
          '--color-edge': '46 58 75',
          '--color-electric': '0 240 255',
          '--color-success': '62 207 142',
          '--color-safe': '0 255 159',
          '--color-amber': '255 191 0',
          '--color-critical': '255 7 58',
          '--color-danger': '239 68 68',
          '--color-canvas': '15 23 42',
        }
      })
    })
  ],
};

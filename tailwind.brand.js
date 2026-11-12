/* Brand tokens as Tailwind utilities. Generated — do not edit.
   Gives you: bg-brand-900, text-brand-700, border-accent-500, ring-brand-500, etc. */
tailwind.config = {
  theme: {
    extend: {
      colors: {
        brand: {
          "50": "#EFF6E9",
          "100": "#E4F0DA",
          "200": "#c7e0b8",
          "300": "#9dc79a",
          "400": "#6ba883",
          "500": "#41866a",
          "600": "#227d47",
          "700": "#164a30",
          "800": "#0D3A29",
          "900": "#08251A",
        },
        accent: {
          "300": "#d3ffa0",
          "400": "#c4ff7d",
          "500": "#ABFF44",
          "600": "#8ee022",
        },
        grass: "#7DDD3D",
        "good-to-go": "#3AB533",
        sky: { DEFAULT: "#91DBDA", soft: "#caedec" },
        pink: "#FF99B6",
      },
      fontFamily: {
        // Body (Die Grotesk B → Inter). Headlines & big stats use `font-display`.
        sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
        display: ['Space Grotesk', 'Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      borderRadius: { xl: '0.875rem', '2xl': '1.25rem' },
      boxShadow: {
        card: '0 1px 2px rgba(16,24,40,.04), 0 4px 16px rgba(16,24,40,.06)',
      },
    },
  },
};

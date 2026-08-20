import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import {
  EB_Garamond,
  Fraunces,
  Instrument_Serif,
  Inter,
} from "next/font/google";

import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const fraunces = Fraunces({
  subsets: ["latin"],
  variable: "--font-fraunces",
  display: "swap",
  axes: ["SOFT", "WONK", "opsz"],
});

const instrument = Instrument_Serif({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-instrument",
  display: "swap",
});

const ebGaramond = EB_Garamond({
  subsets: ["latin"],
  variable: "--font-eb-garamond",
  display: "swap",
});

export const viewport: Viewport = {
  colorScheme: "light",
  themeColor: "#FFFFEB",
  width: "device-width",
  initialScale: 1,
};

export const metadata: Metadata = {
  metadataBase: new URL("https://viberead.ai"),
  title: "Vibe Read | Open source voice dictation for Mac",
  description:
    "A free, open source Mac app for fast dictation, optional Smart Dictation, ElevenLabs or macOS read aloud, and configurable Cmd + E actions.",
  applicationName: "Vibe Read",
  category: "productivity",
  keywords: [
    "macOS dictation",
    "open source dictation",
    "voice typing",
    "text to speech",
    "local-first",
    "Vibe Read",
  ],
  alternates: { canonical: "/" },
  robots: {
    index: true,
    follow: true,
  },
  openGraph: {
    title: "Vibe Read | Open source voice dictation for Mac",
    description:
      "Free and open source direct or Smart Dictation, read aloud, and configurable actions for Mac.",
    url: "/",
    siteName: "Vibe Read",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "Vibe Read | Open source voice dictation for Mac",
    description:
      "Free and open source direct or Smart Dictation, read aloud, and configurable actions for Mac.",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="scroll-smooth">
      <body
        className={`${inter.variable} ${fraunces.variable} ${instrument.variable} ${ebGaramond.variable} bg-[#FFFFEB] font-sans`}
      >
        {children}
      </body>
    </html>
  );
}

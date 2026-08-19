"use client";

import { Button } from "@/components/ui/button";
import { motion } from "framer-motion";
import Link from "next/link";
import { CurvedTextVisualizer } from "./CurvedTextVisualizer";

const GITHUB_URL = "https://github.com/mathias-heide/VibeRead";

export function Hero() {
  return (
    <section id="top" className="relative w-full pb-24 md:pb-40 text-center overflow-hidden pt-48 md:pt-64">
      <motion.div
        initial={false}
        animate={{ opacity: 1, y: 0 }}
        className="max-w-5xl mx-auto flex flex-col items-center relative z-10"
      >
        <h1 className="text-[10vw] sm:text-[8vw] md:text-[4rem] leading-none md:leading-none font-display font-normal text-slate-900 mb-8 tracking-tighter max-w-5xl px-2 md:px-0">
          <span className="text-slate-900/30 select-none font-classic">Stop typing,</span> start talking.
        </h1>

        <p className="text-base md:text-xl text-slate-600 max-w-2xl mb-12 leading-relaxed font-light px-4">
          A small open source Mac app for dictation, read-aloud, and configurable Cmd + E actions. Your history stays on your Mac.
        </p>

        <div className="flex flex-col sm:flex-row gap-4 items-center mb-2">
          <Button asChild size="default" className="h-10 px-5 rounded-full bg-[#E0CCFA] text-black hover:bg-[#D4BBF5] text-sm shadow-lg hover:shadow-xl transition-all hover:-translate-y-0.5 border-2 border-black font-medium">
            <Link href={GITHUB_URL}>
              <svg className="w-3.5 h-3.5 mr-2" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
              View source on GitHub
            </Link>
          </Button>
        </div>

        <p className="text-[10px] text-slate-500 leading-tight">
          Free and open source for Mac.<br />
          MIT licensed.
        </p>
      </motion.div>

      {/* Voice animation - positioned below CTA */}
      <CurvedTextVisualizer />
    </section>
  );
}

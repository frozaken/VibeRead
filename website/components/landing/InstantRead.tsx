"use client";

import { Badge } from "@/components/ui/badge";
import { Play, ArrowRight } from "lucide-react";
import { motion, useReducedMotion } from "framer-motion";
import Link from "next/link";
import { cn } from "@/lib/utils";

interface InstantReadProps {
  theme?: "light" | "dark";
  compact?: boolean;
}

export function InstantReadContent({ theme = "dark", compact = false }: InstantReadProps) {
  const isLight = theme === "light";
  return (
    <div className="flex flex-col items-start text-left">
        <Badge className={cn("mb-6 border-none", isLight ? "bg-slate-100 text-slate-900 hover:bg-slate-200" : "bg-[#FFFFEB] text-black hover:bg-white")}>Your voice</Badge>
        <h3 className={cn("font-display mb-8 leading-[1.1]",
            compact ? "text-3xl md:text-5xl" : "text-4xl md:text-7xl",
            isLight ? "text-slate-900" : "text-[#FFFFEB]")}>
          Read anything<br />out loud.
        </h3>
        <p className={cn("leading-relaxed mb-10 max-w-lg",
            compact ? "text-lg" : "text-xl",
            isLight ? "text-slate-600" : "text-[#FFFFEB]/70")}>
          Select text, open a saved page, or paste a note. Use an ElevenLabs
          voice when you want it, or keep everything offline with the voices
          already on your Mac.
        </p>
        <div className="flex flex-col sm:flex-row gap-6 items-start sm:items-center">
            <div className="flex gap-4">
                <div className={cn("px-4 py-2 rounded-lg text-sm font-mono border",
                    isLight ? "bg-slate-100 text-slate-900 border-slate-200" : "bg-white/10 text-[#E0CCFA] border-white/10")}>
                    ⌘ + ⇧ + E
                </div>
                <span className={cn("self-center text-sm", isLight ? "text-slate-600" : "text-[#FFFFEB]/65")}>to read selection</span>
            </div>
            <Link href="https://github.com/mathias-heide/VibeRead" target="_blank" rel="noreferrer" className={cn("flex items-center text-sm font-medium hover:underline underline-offset-4", isLight ? "text-slate-900" : "text-[#E0CCFA]")}>
                View the source <ArrowRight className="w-4 h-4 ml-1" />
            </Link>
        </div>
    </div>
  );
}

export function InstantReadVisual() {
    const reduceMotion = useReducedMotion();

    return (
        <div className="bg-[#1A1A1A] rounded-[2.5rem] p-8 aspect-square border border-white/10 relative overflow-hidden flex items-center justify-center shadow-2xl h-full w-full">
            <div className="text-center relative z-10">
                <div className="w-16 h-16 bg-[#E0CCFA] rounded-full flex items-center justify-center mx-auto mb-6">
                    <Play className="w-8 h-8 text-black fill-current ml-1" />
                </div>
                <div className="w-64 h-2 bg-[#FFFFEB]/20 rounded-full mx-auto overflow-hidden relative">
                    <motion.div
                        animate={reduceMotion ? { width: "72%" } : { width: ["0%", "100%"] }}
                        transition={reduceMotion ? { duration: 0 } : { duration: 4, repeat: Infinity }}
                        className="h-full bg-[#E0CCFA]"
                    />
                </div>
                <p className="mt-4 text-[#FFFFEB]/60 font-mono text-sm">Reading selection</p>
            </div>
            {/* Simulated text selection background */}
            <div className="absolute inset-0 opacity-10 flex flex-col gap-4 p-8">
                <div className="h-4 bg-[#E0CCFA] w-full rounded"></div>
                <div className="h-4 bg-[#E0CCFA] w-3/4 rounded"></div>
                <div className="h-4 bg-[#E0CCFA] w-full rounded"></div>
                <div className="h-4 bg-[#E0CCFA] w-5/6 rounded"></div>
            </div>
        </div>
    );
}

export function InstantRead({ theme = "dark" }: InstantReadProps) {
  return (
    <div className="flex flex-col md:flex-row-reverse gap-16 items-center">
      <div className="flex-1">
        <InstantReadContent theme={theme} />
      </div>
      <div className="flex-1 w-full">
        <InstantReadVisual />
      </div>
    </div>
  );
}

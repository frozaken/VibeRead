"use client";

import { Badge } from "@/components/ui/badge";
import { ArrowRight, Volume2, WandSparkles } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils";

interface CalmModeFeatureProps {
  theme?: "light" | "dark";
  compact?: boolean;
}

export function CalmModeContent({ theme = "dark", compact = false }: CalmModeFeatureProps) {
  const isLight = theme === "light";
  return (
    <div className="flex flex-col items-start text-left">
      <Badge className={cn("mb-6 border-none", isLight ? "bg-slate-100 text-slate-900 hover:bg-slate-200" : "bg-[#FFFFEB] text-black hover:bg-white")}>Configurable</Badge>
        <h3 className={cn("font-display mb-8 leading-[1.1]",
            compact ? "text-3xl md:text-5xl" : "text-4xl md:text-7xl",
            isLight ? "text-slate-900" : "text-[#FFFFEB]")}>
          Make Cmd + E<br />yours.
        </h3>
        <p className={cn("leading-relaxed mb-10 max-w-lg",
            compact ? "text-lg" : "text-xl",
            isLight ? "text-slate-600" : "text-[#FFFFEB]/70")}>
          Choose which actions appear, change their prompts, or rebind the
          shortcut. Provider-backed results stay in the menu for review before
          you apply them.
        </p>
        <div className="flex flex-col sm:flex-row gap-6 items-start sm:items-center">
            <div className="flex gap-4">
                <div className={cn("px-4 py-2 rounded-lg text-sm font-mono border",
                    isLight ? "bg-slate-100 text-slate-900 border-slate-200" : "bg-white/10 text-[#E0CCFA] border-white/10")}>
                    ⌘ + E
                </div>
                <span className={cn("self-center text-sm", isLight ? "text-slate-600" : "text-[#FFFFEB]/65")}>open your tools</span>
            </div>
            <Link href="https://github.com/mathias-heide/VibeRead" target="_blank" rel="noreferrer" className={cn("flex items-center text-sm font-medium hover:underline underline-offset-4", isLight ? "text-slate-900" : "text-[#E0CCFA]")}>
                View the source <ArrowRight className="w-4 h-4 ml-1" />
            </Link>
        </div>
    </div>
  );
}

export function CalmModeVisual() {
    return (
        <div className="bg-[#1A1A1A] rounded-[2.5rem] p-8 aspect-square border border-white/10 relative overflow-hidden flex items-center justify-center shadow-2xl h-full w-full">
            {/* Overlay simulation */}
            <div className="absolute inset-4 bg-[#FFFFEB] rounded-2xl opacity-10 blur-sm transform scale-95"></div>
            <div className="w-full max-w-sm bg-[#2A2A2A] rounded-xl border border-white/10 p-6 shadow-2xl relative z-10">
                <div className="flex items-center gap-3 mb-4 border-b border-white/5 pb-4">
                    <div className="w-3 h-3 rounded-full bg-red-500"></div>
                    <div className="w-3 h-3 rounded-full bg-yellow-500"></div>
                    <div className="w-3 h-3 rounded-full bg-green-500"></div>
                </div>
                <div className="space-y-3">
                    <div className="flex items-center gap-3 p-3 rounded-lg hover:bg-white/5 cursor-pointer group">
                        <WandSparkles className="text-[#E0CCFA] group-hover:text-white" />
                        <span className="text-[#FFFFEB]/80 group-hover:text-white">Rewrite this clearly</span>
                    </div>
                     <div className="flex items-center gap-3 p-3 rounded-lg hover:bg-white/5 cursor-pointer group">
                        <Volume2 className="text-[#E0CCFA] group-hover:text-white" />
                        <span className="text-[#FFFFEB]/80 group-hover:text-white">Read selection aloud</span>
                    </div>
                </div>
            </div>
        </div>
    );
}

export function CalmModeFeature({ theme = "dark" }: CalmModeFeatureProps) {
  return (
    <div className="flex flex-col md:flex-row-reverse gap-16 items-center">
      <div className="flex-1">
        <CalmModeContent theme={theme} />
      </div>
      <div className="flex-1 w-full">
        <CalmModeVisual />
      </div>
    </div>
  );
}

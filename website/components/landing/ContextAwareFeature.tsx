"use client";

import { Badge } from "@/components/ui/badge";
import { ArrowRight, KeyRound, Laptop, Server, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils";

interface ContextAwareFeatureProps {
  theme?: "light" | "dark";
  compact?: boolean;
}

export function ContextAwareContent({ theme = "dark", compact = false }: ContextAwareFeatureProps) {
  const isLight = theme === "light";
  return (
    <div className="flex flex-col items-start text-left">
        <Badge className="mb-6 bg-[#E0CCFA] text-black hover:bg-[#E0CCFA]/90">Your provider</Badge>
        <h3 className={cn("font-display mb-8 leading-[1.1]",
            compact ? "text-3xl md:text-5xl" : "text-4xl md:text-7xl",
            isLight ? "text-slate-900" : "text-[#FFFFEB]")}>
          Use the model<br />you trust.
        </h3>
        <p className={cn("leading-relaxed mb-10 max-w-lg",
            compact ? "text-lg" : "text-xl",
            isLight ? "text-slate-600" : "text-[#FFFFEB]/70")}>
          Choose ElevenLabs, Groq, OpenRouter, OpenAI, or a compatible custom
          endpoint for dictation. Pick the model and language, then configure
          Cmd + E separately if you want it.
        </p>
        <div className={cn("p-4 rounded-2xl border max-w-md mb-8", isLight ? "bg-slate-50 border-slate-200" : "bg-white/5 border-white/10")}>
            <div className="flex items-center gap-3 mb-2">
                <ShieldCheck className="w-4 h-4 text-[#E0CCFA]" />
                <span className={cn("text-sm font-medium", isLight ? "text-slate-900" : "text-[#FFFFEB]")}>Direct connection</span>
            </div>
            <p className={cn("text-sm", isLight ? "text-slate-500" : "text-[#FFFFEB]/60")}>
                Vibe Read talks to your provider. There is no Vibe Read cloud
                in the middle.
            </p>
        </div>
        <div>
            <Link href="https://github.com/mathias-heide/VibeRead" target="_blank" rel="noreferrer" className={cn("flex items-center text-sm font-medium hover:underline underline-offset-4", isLight ? "text-slate-900" : "text-[#E0CCFA]")}>
                View the source <ArrowRight className="w-4 h-4 ml-1" />
            </Link>
        </div>
    </div>
  );
}

export function ContextAwareVisual() {
    return (
        <div className="bg-[#1A1A1A] rounded-[2.5rem] p-8 aspect-square border border-white/10 relative overflow-hidden group flex flex-col justify-center items-center shadow-2xl h-full w-full">
            <div className="absolute inset-0 bg-linear-to-b from-transparent to-[#0A0A0A]/80 z-0"></div>

            <div className="relative z-10 w-full max-w-sm overflow-hidden rounded-xl border border-white/10 bg-[#222] shadow-2xl transition-transform duration-500 group-hover:-translate-y-1">
                <div className="flex items-center gap-3 border-b border-white/5 p-4">
                    <div className="h-3 w-3 rounded-full bg-red-500"></div>
                    <div className="h-3 w-3 rounded-full bg-yellow-500"></div>
                    <div className="h-3 w-3 rounded-full bg-green-500"></div>
                </div>
                <div className="space-y-3 p-5">
                    <div className="flex items-center gap-3 rounded-lg border border-white/5 bg-white/5 p-4">
                        <KeyRound className="h-5 w-5 text-[#E0CCFA]" />
                        <div>
                            <p className="text-sm text-[#FFFFEB]">Keys stay in Keychain</p>
                            <p className="text-xs text-[#FFFFEB]/45">Read only when you verify or use one</p>
                        </div>
                    </div>
                    <div className="flex items-center gap-3 rounded-lg border border-white/5 bg-white/5 p-4">
                        <Server className="h-5 w-5 text-[#E0CCFA]" />
                        <div>
                            <p className="text-sm text-[#FFFFEB]">Dictation and Cmd + E</p>
                            <p className="text-xs text-[#FFFFEB]/45">Configured separately</p>
                        </div>
                    </div>
                    <div className="flex items-center gap-3 rounded-lg border border-[#E0CCFA]/20 bg-[#E0CCFA]/10 p-4">
                        <Laptop className="h-5 w-5 text-[#E0CCFA]" />
                        <span className="text-sm text-[#E0CCFA]">Local endpoint supported</span>
                    </div>
                </div>
            </div>

         </div>
    );
}

export function ContextAwareFeature({ theme = "dark" }: ContextAwareFeatureProps) {
  return (
    <div className="flex flex-col md:flex-row gap-16 items-center">
      <div className="flex-1">
        <ContextAwareContent theme={theme} />
      </div>
      <div className="flex-1 w-full relative">
         <ContextAwareVisual />
      </div>
    </div>
  );
}

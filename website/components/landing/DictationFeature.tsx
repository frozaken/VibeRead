"use client";

import { Badge } from "@/components/ui/badge";
import { ArrowRight, Check } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils";
import { StreamTextVisualizer } from "@/components/visualizations/StreamTextVisualizer";

interface DictationFeatureProps {
  theme?: "light" | "dark";
}

export function DictationFeature({ theme = "dark" }: DictationFeatureProps) {
  const isLight = theme === "light";

  return (
    <div className="flex scroll-mt-24 flex-col items-center gap-16 md:flex-row" id="dictation">
      <div className="flex-1">
        <Badge className="mb-6 bg-[#E0CCFA] text-black hover:bg-[#E0CCFA]/90">Two clear modes</Badge>
        <h2 className={cn("text-4xl md:text-7xl font-display mb-8 leading-[1.1]", isLight ? "text-slate-900" : "text-[#FFFFEB]")}>
          Don't type,<br />just speak.
        </h2>
        <p className={cn("text-xl leading-relaxed mb-6 max-w-lg", isLight ? "text-slate-600" : "text-[#FFFFEB]/70")}>
          Press Fn once to start and again to send. Normal dictation stays fast
          and uses the speech transcript as-is. It never calls a text model.
        </p>
        <p className={cn("text-lg leading-relaxed mb-10 max-w-lg", isLight ? "text-slate-500" : "text-[#FFFFEB]/60")}>
          Use Fn + Option when you want Smart Dictation to follow spoken
          instructions and produce finished text. If the Smart edit fails,
          Vibe Read keeps the raw transcript.
        </p>
        <ul className={cn("space-y-4 mb-10", isLight ? "text-slate-700" : "text-[#FFFFEB]/80")}>
            <li className="flex items-center gap-3">
                <Check className="w-5 h-5 text-[#E0CCFA]" /> Works across Mac apps
            </li>
            <li className="flex items-center gap-3">
                <Check className="w-5 h-5 text-[#E0CCFA]" /> Local history you control
            </li>
            <li className="flex items-center gap-3">
                <Check className="w-5 h-5 text-[#E0CCFA]" /> No Vibe Read server
            </li>
        </ul>
        <div className="flex flex-col sm:flex-row gap-6 items-start sm:items-center">
            <div className={cn("flex gap-4", isLight ? "" : "")}>
                <div className={cn("px-4 py-2 rounded-lg text-sm font-mono border",
                    isLight ? "bg-slate-100 text-slate-900 border-slate-200" : "bg-white/10 text-[#E0CCFA] border-white/10")}>
                    Fn + Option
                </div>
                <span className={cn("self-center text-sm", isLight ? "text-slate-600" : "text-[#FFFFEB]/65")}>Smart Dictation</span>
            </div>
            <Link href="https://github.com/mathias-heide/VibeRead" target="_blank" rel="noreferrer" className={cn("flex items-center text-sm font-medium hover:underline underline-offset-4", isLight ? "text-slate-900" : "text-[#E0CCFA]")}>
                View the source <ArrowRight className="w-4 h-4 ml-1" />
            </Link>
        </div>
      </div>
      <div className="flex-1 w-full relative">
         <StreamTextVisualizer
            rawText="Um yeah so I think we should probably reach out to uh Jenny from legal I think she said something about the the NDA being like not ready yet"
            processedText="Let's reach out to Jenny from Legal. She may have mentioned the NDA is not finalized yet."
            className="shadow-2xl"
         />
      </div>
    </div>
  );
}

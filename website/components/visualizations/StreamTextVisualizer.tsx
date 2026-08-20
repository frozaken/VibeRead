"use client";

import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useState } from "react";
import { Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";

interface StreamTextProps {
  rawText: string;
  processedText: string;
  className?: string;
}

export function StreamTextVisualizer({ rawText, processedText, className }: StreamTextProps) {
  const words = rawText.split(" ");
  const processedWords = processedText.split(" ");
  const [activeWordIndex, setActiveWordIndex] = useState(0);
  const reduceMotion = useReducedMotion();
  const visibleWordIndex = reduceMotion ? words.length + 5 : activeWordIndex;

  useEffect(() => {
    if (reduceMotion) return;

    const interval = setInterval(() => {
      setActiveWordIndex((prev) => {
        if (prev >= words.length + 5) { // Pause at end
          return 0;
        }
        return prev + 1;
      });
    }, 200); // Speed of words appearing

    return () => clearInterval(interval);
  }, [reduceMotion, words.length]);

  return (
    <div aria-label="Smart Dictation turning spoken instructions into finished text" className={cn("relative w-full h-[400px] bg-[#1A1A1A] rounded-[2.5rem] overflow-hidden border border-white/10", className)} role="img">
      {/* Background Flow Curve */}
      <div className="absolute inset-0 opacity-20 pointer-events-none">
        <svg aria-hidden="true" className="w-full h-full" preserveAspectRatio="none">
          <path
            d="M -100 200 Q 400 200 600 300 T 1200 300"
            fill="none"
            stroke="url(#gradient)"
            strokeWidth="2"
          />
          <defs>
            <linearGradient id="gradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="transparent" />
              <stop offset="50%" stopColor="#E0CCFA" />
              <stop offset="100%" stopColor="transparent" />
            </linearGradient>
          </defs>
        </svg>
      </div>

      {/* Floating Words Stream */}
      <div className="absolute top-1/2 left-0 w-full -translate-y-1/2 flex items-center px-12">
        <div className="relative w-full h-32 overflow-hidden mask-linear-fade">
            {words.map((word, i) => {
                // Calculate position relative to active index
                const offset = i - visibleWordIndex;
                const isVisible = offset > -5 && offset < 5;
                const isPast = offset < 0;

                // Animate horizontally
                return (
                    <motion.div
                        key={i}
                        className={cn(
                            "absolute top-1/2 text-2xl md:text-4xl font-display whitespace-nowrap transition-all duration-300",
                            isPast ? "opacity-0 scale-50" : "opacity-100 scale-100",
                            word.match(/um|uh|like/i) ? "text-[#E0CCFA]/40 decoration-through" : "text-[#E0CCFA]"
                        )}
                        initial={reduceMotion ? false : { x: 1000, opacity: 0 }}
                        animate={{
                            x: offset * 80 + 300, // Move left to right
                            opacity: isVisible ? (word.match(/um|uh|like/i) ? 0.5 : 1) : 0,
                            scale: isVisible ? 1 : 0.8,
                            y: isPast ? 50 : 0 // Drop down effect "into the curve"
                        }}
                        transition={{ type: "spring", stiffness: 100, damping: 20 }}
                    >
                        {word}
                    </motion.div>
                );
            })}
        </div>
      </div>

      {/* Result Box (The "Curve" Destination) */}
      <div className="absolute bottom-12 right-12 left-12">
        <div className="bg-[#2A2A2A] rounded-2xl p-6 border border-white/10 backdrop-blur-sm relative overflow-hidden">
            <div className="absolute top-0 left-0 w-full h-1 bg-linear-to-r from-[#E0CCFA] to-transparent opacity-50"></div>
            <p className="text-[#FFFFEB] text-lg leading-relaxed">
                {processedWords.map((word, i) => (
                    <motion.span
                        key={i}
                        initial={reduceMotion ? false : { opacity: 0, y: 10 }}
                        animate={{
                            opacity: i < visibleWordIndex * 0.7 ? 1 : 0.2, // Reveal slower than raw stream
                            y: i < visibleWordIndex * 0.7 ? 0 : 5
                        }}
                        className="inline-block mr-1.5 transition-all duration-300"
                    >
                        {word}
                    </motion.span>
                ))}
            </p>
            <div className="mt-4 flex items-center gap-2 text-xs text-[#E0CCFA]/60 font-mono uppercase tracking-wider">
                <Sparkles className="w-3 h-3" /> Smart Dictation
            </div>
        </div>
      </div>
    </div>
  );
}

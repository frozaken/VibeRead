"use client";

import { motion, AnimatePresence, useReducedMotion } from "framer-motion";
import { useEffect, useState, useMemo } from "react";
import { cn } from "@/lib/utils";
import { Check } from "lucide-react";

const INPUT_TEXT = "so like um basically I was thinking you know what I mean kind of like maybe we should just go ahead and do it because nobody really knows what's going on so can you check in with them and see if like um the whole thing is ready or whatever I guess we could also maybe try something else but I don't know like I'm not really sure about this whole situation and um maybe we should just wait and see what happens you know what I mean it's kind of complicated and stuff so yeah I think that's probably the best approach for now like honestly I'm not even sure if this is the right way to go about things but whatever you know I mean we'll figure it out eventually I guess it's just one of those things where you have to kind of wing it and hope for the best right like there's no real manual for this stuff so we're just making it up as we go along which is fine I suppose but yeah let me know what you think about all of this whenever you get a chance ";
const OUTPUT_TEXT = "Can you check in with them and see if the notes from yesterday's meeting are ready? I think we should review everything before the call. It might slip through if we don't follow up soon. Let me know what they say and we can plan accordingly. I'll prepare a summary of the key points we discussed, and we can go over any questions or concerns during our next session. This will help ensure we're all on the same page moving forward. I've also compiled the action items from our previous discussion and will share those with the team. Please review the document and let me know if you'd like to add anything or make any changes before we proceed with the next steps. ";

type ScenarioStep = 'input' | 'animating' | 'success';

interface Scenario {
  id: string;
  render: (step: ScenarioStep) => React.ReactNode;
  successLabel: string;
}

const SCENARIOS: Scenario[] = [
  {
    id: "filler",
    render: (step) => (
      <div className="flex items-center text-xl font-medium text-slate-600">
        <motion.span
          layout
          transition={{ duration: 0.3, ease: "easeInOut" }}
        >
          the
        </motion.span>

        <AnimatePresence mode="popLayout">
          {(step === 'input' || step === 'animating') && (
            <motion.span
              layout
              initial={{ opacity: 1, width: "auto", scale: 1 }}
              exit={{ opacity: 0, width: 0, scale: 0 }}
              transition={{ duration: 0.3, ease: "easeInOut" }}
              className="relative inline-block mx-1.5 origin-center overflow-hidden"
            >
              the
              {step === 'animating' && (
                <svg
                  aria-hidden="true"
                  className="absolute inset-0 -left-[10%] w-[120%] h-full overflow-visible pointer-events-none"
                  viewBox="0 0 100 20"
                  preserveAspectRatio="none"
                >
                  <motion.path
                    d="M 0 12 C 30 15 70 5 100 12"
                    fill="none"
                    stroke="#0f766e"
                    strokeWidth="4"
                    strokeLinecap="round"
                    initial={{ pathLength: 0, opacity: 0 }}
                    animate={{ pathLength: 1, opacity: 0.8 }}
                    transition={{ duration: 0.3, ease: "easeInOut" }}
                  />
                </svg>
              )}
            </motion.span>
          )}
        </AnimatePresence>
      </div>
    ),
    successLabel: "Filler removed"
  },
  {
    id: "uhm",
    render: (step) => (
      <div className="flex items-center text-xl font-medium text-slate-600">
        <motion.span
          layout
          transition={{ duration: 0.3, ease: "easeInOut" }}
        >
          so
        </motion.span>

        <AnimatePresence mode="popLayout">
          {(step === 'input' || step === 'animating') && (
            <motion.span
              layout
              initial={{ opacity: 1, width: "auto", scale: 1 }}
              exit={{ opacity: 0, width: 0, scale: 0 }}
              transition={{ duration: 0.3, ease: "easeInOut" }}
              className="relative inline-block mx-1.5 origin-center overflow-hidden"
            >
              uhm
              {step === 'animating' && (
                <svg
                  aria-hidden="true"
                  className="absolute inset-0 -left-[10%] w-[120%] h-full overflow-visible pointer-events-none"
                  viewBox="0 0 100 20"
                  preserveAspectRatio="none"
                >
                  <motion.path
                    d="M 0 12 C 25 8 75 16 100 11"
                    fill="none"
                    stroke="#0f766e"
                    strokeWidth="4"
                    strokeLinecap="round"
                    initial={{ pathLength: 0, opacity: 0 }}
                    animate={{ pathLength: 1, opacity: 0.8 }}
                    transition={{ duration: 0.3, ease: "easeInOut" }}
                  />
                </svg>
              )}
            </motion.span>
          )}
        </AnimatePresence>

        <motion.span
          layout
          transition={{ duration: 0.3, ease: "easeInOut" }}
        >
           can we
        </motion.span>
      </div>
    ),
    successLabel: "Filler removed"
  },
  {
    id: "punctuation",
    render: (step) => (
      <div className="flex items-center gap-0.5 text-xl font-medium text-slate-600">
        <span>waiting</span>
        {(step === 'animating' || step === 'input') && (
           <motion.span
             initial={{ opacity: 0, y: 5, scale: 0.5 }}
             animate={step === 'animating' ? { opacity: 1, y: 0, scale: 1 } : { opacity: 0, y: 5, scale: 0.5 }}
             className="text-teal-600 font-bold"
           >
             ?
           </motion.span>
        )}
      </div>
    ),
    successLabel: "Added question mark"
  }
];

export function CurvedTextVisualizer() {
  const [activeScenarioIndex, setActiveScenarioIndex] = useState(0);
  const [step, setStep] = useState<ScenarioStep | null>(null);
  const [offset, setOffset] = useState(-20);
  const reduceMotion = useReducedMotion();

  // Keep the waveform stable across the server and browser render.
  const voiceBars = useMemo(() =>
    Array.from({ length: 40 }, (_, index) => {
      const baseHeight = 12 + ((index * 17) % 29);
      return {
        baseHeight,
        heights: [
          baseHeight * (0.42 + (index % 3) * 0.04),
          baseHeight * (0.82 + (index % 4) * 0.04),
          baseHeight * (0.46 + (index % 2) * 0.05),
        ],
        duration: 0.55 + (index % 5) * 0.07,
        delay: (index % 4) * 0.025,
      };
    }), []
  );

  // Scenario cycling
  useEffect(() => {
    if (reduceMotion) {
      setStep("success");
      return;
    }

    let timeoutId: NodeJS.Timeout;

    const runCycle = () => {
      // 1. Show Input (Start)
      setStep('input');

      // 2. Animate Fix
      timeoutId = setTimeout(() => {
        setStep('animating');

        // 3. Show Success Badge
        timeoutId = setTimeout(() => {
          setStep('success');

          // 4. Clear and Next
          timeoutId = setTimeout(() => {
            setStep(null);

            timeoutId = setTimeout(() => {
              setActiveScenarioIndex(prev => (prev + 1) % SCENARIOS.length);
              runCycle(); // Loop
            }, 500); // Wait bit before next scenario

          }, 2000); // Duration of Success state

        }, 1500); // Duration of Animating state

      }, 1000); // Duration of Input state
    };

    // Start initial cycle
    runCycle();

    return () => clearTimeout(timeoutId);
  }, [reduceMotion]);

  // Animate input text
  useEffect(() => {
    if (reduceMotion) return;

    let animationFrameId: number;
    const animate = () => {
      setOffset(prev => {
        const next = prev + 0.015;
        return next > 40 ? -20 : next;
      });
      animationFrameId = requestAnimationFrame(animate);
    };
    animationFrameId = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animationFrameId);
  }, [reduceMotion]);

  const currentScenario = SCENARIOS[activeScenarioIndex];

  return (
    <div aria-hidden="true" className="w-full relative mt-8 md:mt-16 overflow-hidden">
      {/* Container - fixed height, clips overflow */}
      <div className="relative h-48 md:h-60 flex items-center justify-center">

        {/* === INPUT: Grey curved text - FIXED SIZE, no scaling === */}
        <svg
          aria-hidden="true"
          className="absolute hidden md:block pointer-events-none"
          width="1000"
          height="400"
          viewBox="0 0 1000 400"
          style={{
            top: "50%",
            right: "50%",
            transform: "translateY(-50%)",
          }}
        >
          <defs>
            <path
              id="inputCurve"
              d="M -200 120 Q 0 120 200 180 Q 400 240 600 250 Q 800 235 1000 235"
              fill="none"
            />
          </defs>
          <text className="fill-slate-400/40 font-display" style={{ fontSize: "18px" }}>
            <textPath href="#inputCurve" startOffset={`${offset}%`}>
              {INPUT_TEXT}{INPUT_TEXT}{INPUT_TEXT}{INPUT_TEXT}{INPUT_TEXT}{INPUT_TEXT}
            </textPath>
          </text>
        </svg>

        {/* === CENTER: Voice Pill === */}
        <div className="relative z-30 flex flex-col items-center">
          {/* Tooltip/Visualizer above pill */}
          <div className="mb-6 h-12 flex items-end justify-center">
            <AnimatePresence mode="wait">
              {step && step !== 'success' && (
                <motion.div
                  key={`edit-${currentScenario.id}`}
                  initial={{ opacity: 0, y: 24, scale: 0.9 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -10, scale: 0.9 }}
                  transition={{ type: "spring", stiffness: 400, damping: 25 }}
                >
                  {currentScenario.render(step)}
                </motion.div>
              )}

              {step === 'success' && (
                <motion.div
                  key={`success-${currentScenario.id}`}
                  initial={{ opacity: 0, y: 10, scale: 0.95 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -10, scale: 0.95 }}
                  transition={{ duration: 0.2 }}
                  className={cn(
                    "flex items-center gap-2 px-5 py-2.5 rounded-full text-base font-semibold shadow-lg",
                    "bg-teal-700 text-white"
                  )}
                >
                  <Check className="w-5 h-5 flex-shrink-0" />
                  <span>
                    {currentScenario.successLabel}
                  </span>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* Voice Pill - simple, no shadow, black border */}
          <div className="relative">
            <div className="bg-[#FFFFEB] border-2 border-black px-4 py-5 rounded-full flex gap-[2px] items-center justify-center h-20 w-full">
              {voiceBars.map((bar, i) => (
                <motion.div
                  key={i}
                  className="w-[2px] bg-slate-800 rounded-full"
                  animate={reduceMotion ? { height: bar.baseHeight * 0.7 } : { height: bar.heights }}
                  transition={reduceMotion ? undefined : {
                    duration: bar.duration,
                    repeat: Infinity,
                    delay: i * 0.02 + bar.delay,
                    ease: "easeInOut"
                  }}
                />
              ))}
            </div>
          </div>
        </div>

        {/* === OUTPUT: Black bar === */}
        <div
          className="absolute hidden md:block pointer-events-none z-10"
          style={{
            top: "50%",
            left: "50%",
            right: 0,
            height: "36px",
            transform: "translateY(-50%) translateY(28px)",
            marginLeft: "70px",
          }}
        >
          <div className="absolute inset-0 bg-[#0A0A0A]" />

          <div className="relative h-full overflow-hidden flex items-center">
            <motion.div
              className="absolute flex whitespace-nowrap pl-5"
              animate={reduceMotion ? undefined : { x: ["-50%", "0%"] }}
              transition={reduceMotion ? undefined : {
                duration: 200,
                ease: "linear",
                repeat: Infinity,
              }}
            >
              <span className="font-display text-[#FDFCF6]" style={{ fontSize: "18px" }}>
                {OUTPUT_TEXT}{OUTPUT_TEXT}{OUTPUT_TEXT}{OUTPUT_TEXT}{OUTPUT_TEXT}{OUTPUT_TEXT}
              </span>
            </motion.div>
          </div>
        </div>

      </div>
    </div>
  );
}

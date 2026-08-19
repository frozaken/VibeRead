"use client";

import { motion, useReducedMotion } from "framer-motion";
import { Check, Clock3, HardDrive, Trash2 } from "lucide-react";

import { BottomCTA } from "@/components/landing/BottomCTA";
import {
  CalmModeContent,
  CalmModeVisual,
} from "@/components/landing/CalmModeFeature";
import {
  ContextAwareContent,
  ContextAwareVisual,
} from "@/components/landing/ContextAwareFeature";
import { DictationFeature } from "@/components/landing/DictationFeature";
import { FAQ } from "@/components/landing/FAQ";
import { Footer } from "@/components/landing/Footer";
import { Hero } from "@/components/landing/Hero";
import {
  InstantReadContent,
  InstantReadVisual,
} from "@/components/landing/InstantRead";
import { LogoCloud } from "@/components/landing/LogoCloud";
import { Navbar } from "@/components/landing/Navbar";

const marqueeItems = [
  "Dictate in any app",
  "Read selected text aloud",
  "Make Cmd + E yours",
  "Keep history on your Mac",
];

function MarqueeItems() {
  return (
    <>
      {marqueeItems.map((item, index) => (
        <div className="flex items-center gap-16 pr-16" key={item}>
          <span className={index % 2 === 0 ? "opacity-40" : undefined}>
            {item}
          </span>
          <span className="h-3 w-3 shrink-0 rounded-full bg-[#E0CCFA]" />
        </div>
      ))}
    </>
  );
}

export default function Home() {
  const reduceMotion = useReducedMotion();

  return (
    <div className="flex min-h-screen flex-col overflow-x-hidden bg-[#FFFFEB] font-sans text-slate-900 selection:bg-[#E0CCFA] selection:text-slate-900">
      <Navbar />

      <main className="flex-1">
        <Hero />

        <div
          aria-label="Vibe Read features"
          className="relative w-full overflow-hidden border-y border-black/5 bg-[#0A0A0A] py-10 text-[#FDFCF6]"
          role="region"
        >
          <motion.div
            aria-hidden="true"
            animate={reduceMotion ? undefined : { x: ["0%", "-50%"] }}
            className="flex w-max items-center whitespace-nowrap pr-16 font-display text-4xl md:text-6xl"
            transition={
              reduceMotion
                ? undefined
                : { duration: 80, ease: "linear", repeat: Infinity }
            }
          >
            <MarqueeItems />
            <MarqueeItems />
          </motion.div>
        </div>

        <LogoCloud />

        <section
          className="bg-[#0A0A0A] px-6 py-32 text-[#FFFFEB]"
          id="features"
        >
          <div className="container mx-auto max-w-6xl">
            <DictationFeature theme="dark" />
          </div>
        </section>

        <section
          className="bg-[#FFFFEB] px-6 py-32 text-slate-900"
          id="how-it-works"
        >
          <div className="container mx-auto max-w-6xl">
            <div className="mx-auto mb-20 max-w-3xl text-center">
              <h2 className="mb-6 font-display text-4xl leading-tight md:text-6xl">
                One shortcut.<br />Your tools.
              </h2>
              <p className="text-xl text-slate-600">
                Press{" "}
                <span className="mx-1 rounded bg-slate-200 px-1.5 py-0.5 font-mono text-base text-slate-900">
                  Cmd + E
                </span>{" "}
                anywhere to open your tools. Rebind the shortcut and choose the
                actions that fit how you work.
              </p>
            </div>

            <div className="grid grid-cols-1 gap-8 md:grid-cols-2">
              <div className="col-span-1 scroll-mt-24 rounded-[2.5rem] border border-slate-200 bg-slate-50 p-8 md:col-span-2 md:p-12" id="cmd-e">
                <div className="flex flex-col items-center gap-12 md:flex-row">
                  <div className="flex-1">
                    <CalmModeContent theme="light" />
                  </div>
                  <div className="w-full max-w-md flex-1">
                    <CalmModeVisual />
                  </div>
                </div>
              </div>

              <div className="col-span-1 flex scroll-mt-24 flex-col justify-between rounded-[2.5rem] border border-slate-200 bg-slate-50 p-8 md:p-12">
                <div className="mb-8">
                  <ContextAwareContent compact theme="light" />
                </div>
                <div className="mt-auto aspect-square w-full">
                  <ContextAwareVisual />
                </div>
              </div>

              <div className="col-span-1 flex scroll-mt-24 flex-col justify-between rounded-[2.5rem] border border-slate-200 bg-slate-50 p-8 md:p-12" id="read-aloud">
                <div className="mb-8">
                  <InstantReadContent compact theme="light" />
                </div>
                <div className="mt-auto aspect-square w-full">
                  <InstantReadVisual />
                </div>
              </div>
            </div>
          </div>
        </section>

        <section
          className="bg-[#0A0A0A] px-6 py-32 text-[#FFFFEB]"
          id="privacy"
        >
          <div className="container mx-auto max-w-6xl">
            <div className="mx-auto mb-20 max-w-3xl text-center">
              <h2 className="mb-6 font-display text-4xl leading-tight md:text-6xl">
                Local by default.
              </h2>
              <p className="text-xl text-[#FFFFEB]/70">
                History stays on your Mac. Processing goes only to the
                providers you choose.
              </p>
            </div>

            <div className="grid grid-cols-1 gap-8 md:grid-cols-2">
              <article className="flex flex-col rounded-[2.5rem] border border-white/10 bg-white/5 p-8 md:p-12">
                <div className="mb-8 flex flex-wrap gap-3">
                  <span className="rounded-md bg-[#E0CCFA] px-3 py-1 text-xs font-semibold text-black">
                    On your Mac
                  </span>
                  <span className="rounded-md bg-white/10 px-3 py-1 text-xs font-semibold text-[#FFFFEB]">
                    Local only
                  </span>
                </div>
                <h3 className="mb-6 font-display text-4xl leading-[1.1] md:text-5xl">
                  Keep history<br />on your Mac.
                </h3>
                <p className="mb-10 text-lg leading-relaxed text-[#FFFFEB]/70">
                  Recent dictations stay in local history so you can copy or
                  retry them. Nothing is written to a Vibe Read cloud database.
                  Your chosen provider still receives content for processing.
                </p>

                <div className="mt-auto rounded-3xl border border-white/10 bg-[#1A1A1A] p-6">
                  <div className="mb-5 flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-[#FFFFEB]">
                        Recent dictations
                      </p>
                      <p className="text-sm text-[#FFFFEB]/50">
                        Stored on this Mac
                      </p>
                    </div>
                    <HardDrive className="h-6 w-6 text-[#E0CCFA]" />
                  </div>
                  <div className="space-y-3">
                    {[
                      "Send the revised notes tomorrow morning",
                      "Move the review call to Thursday",
                      "Add the setup steps to the readme",
                    ].map((text) => (
                      <div
                        className="flex items-center gap-3 rounded-xl border border-white/5 bg-white/5 p-3 text-sm text-[#FFFFEB]/70"
                        key={text}
                      >
                        <Check className="h-4 w-4 shrink-0 text-[#E0CCFA]" />
                        <span>{text}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </article>

              <article className="flex flex-col rounded-[2.5rem] border border-white/10 bg-white/5 p-8 md:p-12">
                <div className="mb-8 flex flex-wrap gap-3">
                  <span className="rounded-md bg-[#E0CCFA] px-3 py-1 text-xs font-semibold text-black">
                    Automatic cleanup
                  </span>
                  <span className="rounded-md bg-white/10 px-3 py-1 text-xs font-semibold text-[#FFFFEB]">
                    Seven days
                  </span>
                </div>
                <h3 className="mb-6 font-display text-4xl leading-[1.1] md:text-5xl">
                  Old audio cleans<br />itself up.
                </h3>
                <p className="mb-8 text-lg leading-relaxed text-[#FFFFEB]/70">
                  Retry files are removed after seven days by default. Change
                  the retention period or clear everything whenever you want.
                  Immediate cleanup also removes failed recordings.
                </p>
                <ul className="mb-10 space-y-4 text-[#FFFFEB]/80">
                  {[
                    "Seven days by default",
                    "Immediate means immediate",
                    "Clear anytime in settings",
                  ].map((text) => (
                    <li className="flex items-center gap-3" key={text}>
                      <Check className="h-5 w-5 text-[#E0CCFA]" />
                      {text}
                    </li>
                  ))}
                </ul>

                <div className="mt-auto flex items-center justify-between rounded-3xl border border-white/10 bg-[#1A1A1A] p-6">
                  <div className="flex items-center gap-4">
                    <div className="flex h-14 w-14 items-center justify-center rounded-full bg-[#E0CCFA] text-black">
                      <Clock3 className="h-6 w-6" />
                    </div>
                    <div>
                      <p className="font-semibold text-[#FFFFEB]">
                        Audio retention
                      </p>
                      <p className="text-sm text-[#FFFFEB]/50">
                        Change it whenever you like
                      </p>
                    </div>
                  </div>
                  <Trash2 className="h-6 w-6 text-[#FFFFEB]/40" />
                </div>
              </article>
            </div>
          </div>
        </section>

        <FAQ />
        <BottomCTA />
      </main>

      <Footer />
    </div>
  );
}

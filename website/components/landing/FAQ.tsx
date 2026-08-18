"use client";

import { useId, useState } from "react";
import { motion, AnimatePresence, useReducedMotion } from "framer-motion";
import { ChevronDown } from "lucide-react";

function FAQItem({ question, answer }: { question: string; answer: string }) {
  const [isOpen, setIsOpen] = useState(false);
  const answerId = useId();
  const reduceMotion = useReducedMotion();

  return (
    <div className="border border-black/10 rounded-2xl overflow-hidden bg-white">
      <button
        aria-controls={answerId}
        aria-expanded={isOpen}
        onClick={() => setIsOpen(!isOpen)}
        className="w-full px-6 py-5 text-left flex items-center justify-between gap-4 hover:bg-slate-50 transition-colors"
        type="button"
      >
        <span className="font-medium text-lg text-slate-900">{question}</span>
        <ChevronDown className={`w-5 h-5 text-slate-400 transition-transform duration-200 ${isOpen ? 'rotate-180' : ''}`} />
      </button>
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: reduceMotion ? 0 : 0.2 }}
            className="overflow-hidden"
          >
            <div className="px-6 pb-5 text-slate-600 leading-relaxed" id={answerId}>
              {answer}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export function FAQ() {
  return (
    <section id="faq" className="py-20 px-6 bg-[#FFFFEB] border-t border-black/5">
      <div className="container mx-auto max-w-4xl">
        <div className="text-center mb-12">
          <h2 className="text-4xl md:text-5xl font-display mb-4">Frequently Asked Questions</h2>
          <p className="text-xl text-slate-600">Everything you need to know about running Vibe Read on your Mac</p>
        </div>

        <div className="space-y-4">
          <FAQItem
            question="What is Vibe Read?"
            answer="Vibe Read is a free and open source Mac app for voice dictation, macOS read-aloud, and configurable Cmd + E actions."
          />
          <FAQItem
            question="Does Vibe Read upload my dictations?"
            answer="Vibe Read has no cloud database. Dictation history stays on your Mac. Audio goes only to the OpenAI compatible provider you configure."
          />
          <FAQItem
            question="Do I need an account or subscription?"
            answer="No. There is no Vibe Read account, billing, team workspace, or product analytics."
          />
          <FAQItem
            question="What happens to local audio files?"
            answer="Local audio files are removed after seven days by default. You can change the retention period or clear them sooner in settings."
          />
          <FAQItem
            question="Which AI providers work?"
            answer="Add your own key and base URL for an OpenAI-compatible provider. You can also point the app at a compatible service running locally."
          />
          <FAQItem
            question="Can I change Cmd + E?"
            answer="Yes. Rebind the shortcut and choose or edit the actions it opens."
          />
          <FAQItem
            question="Can I change the source?"
            answer="Yes. Vibe Read is available under the MIT License, so you can read it, fork it, and make it yours."
          />
        </div>
      </div>
    </section>
  );
}

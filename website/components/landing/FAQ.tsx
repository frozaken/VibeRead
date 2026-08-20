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
            answer="Vibe Read is a free and open source Mac app for fast voice dictation, optional Smart Dictation, read-aloud, a local reading Library, and configurable Cmd + E actions."
          />
          <FAQItem
            question="Does Vibe Read upload my dictations?"
            answer="Vibe Read has no cloud database. History stays on your Mac. Recorded audio goes directly to the dictation provider you choose. Normal Fn dictation stops there. Smart Dictation also sends the raw transcript, your local Smart prompt, and a sanitized target app name to your chosen text provider."
          />
          <FAQItem
            question="What is Smart Dictation?"
            answer="Smart Dictation is a separate Fn + Option mode for spoken requests such as drafting an email or formatting a list. It uses your configured text provider after speech-to-text. If that edit fails, Vibe Read keeps the raw transcript."
          />
          <FAQItem
            question="Does it ask for permissions at launch?"
            answer="No. Vibe Read does not show system permission prompts at startup. macOS access is requested only after you click Grant Access or intentionally use a feature that needs it."
          />
          <FAQItem
            question="Do I need an account or subscription?"
            answer="There is no Vibe Read account, billing, team workspace, or product analytics. A remote AI provider may require its own account, API key, and usage payment."
          />
          <FAQItem
            question="What happens to local audio files?"
            answer="Local audio files are removed after seven days by default. You can change the period or clear them sooner. The Immediately option removes successful and failed recordings as soon as their result is recorded, so failed dictations cannot be retried."
          />
          <FAQItem
            question="Which AI providers work?"
            answer="Dictation supports ElevenLabs, Groq, OpenRouter, OpenAI, and compatible custom endpoints. Smart Dictation and Cmd + E can use OpenRouter, Groq, OpenAI, or a custom endpoint independently. ElevenLabs can also power read-aloud with an explicit voice browser and preview."
          />
          <FAQItem
            question="Does it work offline?"
            answer="macOS read-aloud, the local Library, and local actions can work offline. ElevenLabs read-aloud, dictation, page capture, Smart Dictation, and provider-backed actions need a network connection unless you use a compatible local service."
          />
          <FAQItem
            question="Can I change Cmd + E?"
            answer="Yes. Rebind the shortcut and add, edit, or delete custom actions in the app. Read and Save work on selected text or copied links. Provider-backed results stay available to preview, copy, cancel, or apply."
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

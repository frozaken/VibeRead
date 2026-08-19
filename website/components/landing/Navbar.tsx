"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Menu, X } from "lucide-react";
import { useState } from "react";

const GITHUB_URL = "https://github.com/mathias-heide/VibeRead";

export function Navbar() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);

  return (
    <>
      <header className="fixed top-0 z-50 w-full bg-[#FFFFEB]/80 backdrop-blur-md">
        <div className="container mx-auto px-6 h-20 flex items-center justify-between relative">
          <Link href="#top" className="flex items-center gap-3 cursor-pointer group">
            <div className="relative w-10 h-10 overflow-hidden group-hover:scale-105 transition-transform duration-300">
              <img src="/apple-icon.png" alt="Vibe Read" className="w-full h-full object-cover" />
            </div>
            <span className="font-display text-2xl tracking-tight text-slate-900">Vibe Read</span>
          </Link>

          <div className="hidden md:flex absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 items-center gap-8 text-sm font-medium text-slate-600">
            <div className="relative group">
                <Link href="#features" className="hover:text-black transition-colors py-2">Features</Link>
                <div className="absolute top-full left-1/2 -translate-x-1/2 pt-2 opacity-0 translate-y-2 pointer-events-none group-hover:opacity-100 group-hover:translate-y-0 group-hover:pointer-events-auto group-focus-within:opacity-100 group-focus-within:translate-y-0 group-focus-within:pointer-events-auto transition-all duration-200">
                    <div className="bg-white rounded-xl shadow-xl border border-black/5 p-2 w-48 flex flex-col gap-1 overflow-hidden">
                        <Link href="#dictation" className="px-4 py-2 hover:bg-slate-50 rounded-lg text-left text-slate-900">Dictation</Link>
                        <Link href="#read-aloud" className="px-4 py-2 hover:bg-slate-50 rounded-lg text-left text-slate-900">Read aloud</Link>
                        <Link href="#cmd-e" className="px-4 py-2 hover:bg-slate-50 rounded-lg text-left text-slate-900">Cmd + E actions</Link>
                    </div>
                </div>
            </div>
            <Link href="#how-it-works" className="hover:text-black transition-colors">How it works</Link>
            <Link href="#privacy" className="hover:text-black transition-colors">Privacy</Link>
            <Link href={GITHUB_URL} className="hover:text-black transition-colors">GitHub</Link>
          </div>

          <div className="flex items-center gap-4">
            <Button asChild size="lg" className="hidden md:flex rounded-full px-6 bg-[#E0CCFA] text-black hover:bg-[#D4BBF5] border border-black/5 shadow-sm font-medium transition-all hover:scale-105 active:scale-95">
              <Link href={GITHUB_URL}>
                View on GitHub
              </Link>
            </Button>
            <button
              aria-controls="mobile-navigation"
              aria-expanded={isMenuOpen}
              aria-label={isMenuOpen ? "Close navigation" : "Open navigation"}
              className="md:hidden p-2"
              onClick={() => setIsMenuOpen(!isMenuOpen)}
              type="button"
            >
              {isMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </header>

      {/* Mobile Menu */}
      {isMenuOpen && (
        <div className="fixed inset-0 z-40 bg-[#FFFFEB] pt-24 px-6 md:hidden flex flex-col" id="mobile-navigation">
          <nav className="flex flex-col gap-6 text-xl font-serif">
            <Link href="#dictation" onClick={() => setIsMenuOpen(false)}>Dictation</Link>
            <Link href="#read-aloud" onClick={() => setIsMenuOpen(false)}>Read aloud</Link>
            <Link href="#cmd-e" onClick={() => setIsMenuOpen(false)}>Cmd + E actions</Link>
            <div className="h-px bg-black/10 my-2"></div>
            <Link href="#how-it-works" onClick={() => setIsMenuOpen(false)}>How it works</Link>
            <Link href="#privacy" onClick={() => setIsMenuOpen(false)}>Privacy</Link>
            <Link href="#faq" onClick={() => setIsMenuOpen(false)}>FAQ</Link>
          </nav>

          <div className="mt-auto pb-12">
            <Button asChild size="lg" className="w-full rounded-full px-6 bg-[#E0CCFA] text-black hover:bg-[#D4BBF5] border border-black/5 shadow-sm font-medium h-14 text-lg">
              <Link href={GITHUB_URL} onClick={() => setIsMenuOpen(false)}>
                View source on GitHub
              </Link>
            </Button>
            <p className="text-center text-sm text-slate-500 mt-4">
              Free and open source for Mac
            </p>
          </div>
        </div>
      )}
    </>
  );
}

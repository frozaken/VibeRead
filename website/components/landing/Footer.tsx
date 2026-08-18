"use client";

import Link from "next/link";

const GITHUB_URL = "https://github.com/mathias-heide/VibeRead";

export function Footer() {
  return (
    <footer className="py-24 px-6 border-t border-black/5 bg-[#FFFFEB]">
      <div className="container mx-auto">
          <div className="flex flex-col items-center justify-center pt-12">
              <p className="text-[12vw] md:text-[15vw] leading-none font-display font-medium tracking-tight mb-12 select-none text-slate-900">
                  Vibe Read
              </p>

              <div className="w-full grid grid-cols-2 md:grid-cols-4 gap-8 text-sm border-t border-black/5 pt-8 mb-8">
                  <div>
                      <p className="font-medium text-slate-900 mb-4">Product</p>
                      <div className="flex flex-col gap-3 text-slate-500">
                          <Link href="#dictation" className="hover:text-black">Dictation</Link>
                          <Link href="#read-aloud" className="hover:text-black">Read aloud</Link>
                          <Link href="#cmd-e" className="hover:text-black">Cmd + E actions</Link>
                      </div>
                  </div>
                  <div>
                      <p className="font-medium text-slate-900 mb-4">Source</p>
                      <div className="flex flex-col gap-3 text-slate-500">
                          <Link href={GITHUB_URL} className="hover:text-black">GitHub</Link>
                          <Link href={`${GITHUB_URL}#readme`} className="hover:text-black">Setup</Link>
                          <Link href={`${GITHUB_URL}/blob/main/LICENSE`} className="hover:text-black">MIT License</Link>
                      </div>
                  </div>
                  <div>
                      <p className="font-medium text-slate-900 mb-4">Privacy</p>
                      <div className="flex flex-col gap-3 text-slate-500">
                          <Link href="#privacy" className="hover:text-black">Local history</Link>
                          <Link href="#privacy" className="hover:text-black">Audio cleanup</Link>
                          <Link href="#how-it-works" className="hover:text-black">Local setup</Link>
                      </div>
                  </div>
                  <div>
                      <p className="font-medium text-slate-900 mb-4">Project</p>
                      <div className="flex flex-col gap-3 text-slate-500">
                          <Link href="#faq" className="hover:text-black">FAQ</Link>
                          <Link href="#source" className="hover:text-black">View source</Link>
                          <Link href="#top" className="hover:text-black">Back to top</Link>
                      </div>
                  </div>
              </div>

              {/* Copyright & Trust Badges */}
              <div className="w-full border-t border-black/5 pt-6">
                <div className="flex flex-col md:flex-row justify-between items-center gap-4 text-sm text-slate-500">
                  <p className="text-center md:text-left">
                    <span className="block md:inline">© 2026 Vibe Read.</span>
                    <span className="block md:inline md:ml-1">Free and open source under the MIT License.</span>
                  </p>
                  <div className="flex flex-wrap justify-center gap-x-4 md:gap-x-6 gap-y-2 text-slate-500 text-xs md:text-sm">
                    <div className="flex items-center gap-1.5">
                      <span>⌘</span>
                      <span>Local first</span>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <span>●</span>
                      <span>Mac app</span>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <span>⌘</span>
                      <span>MIT licensed</span>
                    </div>
                  </div>
                </div>
              </div>
          </div>
      </div>
    </footer>
  );
}

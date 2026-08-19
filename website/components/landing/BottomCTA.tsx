"use client";

import { Button } from "@/components/ui/button";
import Link from "next/link";

const GITHUB_URL = "https://github.com/mathias-heide/VibeRead";

export function BottomCTA() {
  return (
    <section id="source" className="relative flex min-h-[36rem] items-center justify-center overflow-hidden py-20 md:min-h-[80vh]">
        <div className="absolute inset-0 z-0">
            <div className="absolute inset-0 bg-[#00332C]/80 z-10 mix-blend-multiply"></div>
            <div className="relative w-full h-full overflow-hidden bg-[#00332C]">
                <div className="absolute -top-24 -left-16 w-[34rem] h-[34rem] rounded-full bg-[#E0CCFA]/70 blur-[110px]"></div>
                <div className="absolute -bottom-32 right-0 w-[42rem] h-[42rem] rounded-full bg-[#FFFFEB]/25 blur-[130px]"></div>
                <div className="absolute inset-y-0 left-1/2 w-40 -skew-x-12 bg-[#E0CCFA]/15 blur-2xl"></div>
            </div>
        </div>

        <div className="relative z-20 text-center px-6 max-w-4xl">
            <h2 className="text-5xl md:text-9xl font-display text-[#FDFCF6] mb-8 tracking-tighter">
                Build your own Vibe Read.
            </h2>
            <p className="text-xl md:text-2xl text-[#FFFFEB]/80 mb-12 max-w-2xl mx-auto font-light">
                Clone the repo, choose your providers and models, add your keys,
                and build the Mac app in Xcode. Use your own bundle identifier
                and signing identity if you distribute a fork.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
                <Button asChild size="xl" className="h-16 px-10 rounded-full bg-[#E0CCFA] text-black hover:bg-[#D4BBF5] text-xl font-medium border border-black/5">
                    <Link href={GITHUB_URL}>
                        View on GitHub
                    </Link>
                </Button>
            </div>
            <p className="mt-6 text-[#FFFFEB]/50 text-sm">
                Free and open source under the MIT License.
            </p>
        </div>
    </section>
  );
}

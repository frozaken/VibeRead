"use client";

export function LogoCloud() {
  return (
    <section className="py-20 bg-[#00332C] text-[#FDFCF6]">
        <p className="text-center text-sm font-medium text-[#FFFFEB]/60 mb-12 uppercase tracking-widest font-sans">
            I built Vibe Read to do a few things well and keep the rest simple
        </p>
        <div className="flex flex-wrap justify-center gap-x-16 gap-y-10 px-6 opacity-80">
            {['Dictation', 'Read aloud', 'Cmd + E', 'Local history', 'Your API key', 'Open source'].map((logo) => (
                <span key={logo} className="text-2xl font-semibold font-serif flex items-center gap-3">
                    {logo}
                </span>
            ))}
        </div>
    </section>
  );
}

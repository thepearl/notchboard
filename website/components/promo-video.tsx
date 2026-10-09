import poster from '@/public/notchboard-promo-poster.jpg';

// The promo video (built from the repo's promo/ Remotion project and copied to public/).
// Muted autoplay is the only autoplay browsers allow, and the video has no sound anyway; the
// captions carry everything. The poster is a static import so it gets the base path for free,
// the video src is in public/ and needs it added by hand.
const src = `${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}/notchboard-promo.mp4`;

export function PromoVideo({ className }: { className?: string }) {
  return (
    <video
      className={className ?? 'w-full rounded-lg border'}
      src={src}
      poster={poster.src}
      width={1920}
      height={1080}
      autoPlay
      muted
      loop
      playsInline
      controls
      preload="metadata"
      aria-label="A 44-second demo: Notchboard docks to the iOS Simulator, finds a test account, logs it into the app with a deeplink, marks it in use, syncs through an encrypted team room, and docks to the Android emulator too."
    />
  );
}

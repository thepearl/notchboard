import Image from 'next/image';
import Link from 'next/link';
import type { Metadata } from 'next';
import { Card, Cards } from 'fumadocs-ui/components/card';
import { Book, Cable, CircleQuestionMark, RotateCcwClock } from 'lucide-react';
import icon from '@/public/notchboard-icon.png';
import panel from '@/public/panel-docked-brewly.jpg';

export const metadata: Metadata = {
  description:
    'Shared test accounts and fixtures, docked to the iOS Simulator window, so mobile teams stop hunting for working logins in Slack.',
};

const features = [
  'A docked panel that tracks the Simulator window as it moves and never steals focus from it.',
  'A shared catalogue of accounts, promo codes and fixtures that shows who is using what, and since when.',
  'Secret values that live in the macOS Keychain, never in a plaintext file.',
  'One-click login that fires a deeplink straight into the booted app.',
  'Encrypted exports for moving a collection between Macs, and encrypted local snapshots as the undo.',
  'Team rooms that sync end-to-end encrypted over an MQTT broker you choose. The broker only relays bytes it cannot read.',
  'Keyboard-first control, with global shortcuts to open the panel and add an element.',
];

export default function HomePage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-10 px-6 py-16">
      <section className="flex flex-col items-center gap-4 text-center">
        <Image src={icon} alt="The Notchboard app icon" width={96} height={96} priority />
        <h1 className="text-4xl font-bold">Notchboard</h1>
        <p className="max-w-xl text-fd-muted-foreground">
          A macOS menu-bar app that keeps your team&apos;s working test logins next to the simulator
          you are already looking at. Pick an account, copy it or fire it straight into the booted
          app, and mark it in use so nobody logs in behind you. Open source under Apache-2.0 and
          local-first: nothing leaves your Mac until a collection joins an end-to-end-encrypted team
          room on a broker you choose.
        </p>
      </section>

      <section>
        <h2 className="mb-3 text-xl font-semibold">Install</h2>
        <pre className="overflow-x-auto rounded-lg border bg-fd-secondary p-4 text-sm">
          <code>brew install --cask thepearl/tap/notchboard</code>
        </pre>
        <p className="mt-3 text-sm text-fd-muted-foreground">
          The download is signed with a Developer ID certificate and notarised by Apple, so the
          first launch is a double click. The app has no Dock icon. Look for the square in the menu
          bar.
        </p>
      </section>

      <Image
        src={panel}
        alt="The panel docked beside a simulator running the Brewly demo app's login screen"
        className="rounded-lg border"
      />

      <section>
        <h2 className="mb-3 text-xl font-semibold">What you get</h2>
        <ul className="list-disc space-y-2 ps-5 text-fd-muted-foreground">
          {features.map((feature) => (
            <li key={feature}>{feature}</li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-3 text-xl font-semibold">Where to go next</h2>
        <Cards>
          <Card
            icon={<Book />}
            href="/documentation"
            title="Documentation"
            description="Installing, day-to-day use, team rooms and settings."
          />
          <Card
            icon={<RotateCcwClock />}
            href="/changelog"
            title="Changelog"
            description="What each release changed."
          />
          <Card
            icon={<CircleQuestionMark />}
            href="/help-center"
            title="Help center"
            description="When something does not behave."
          />
          <Card
            icon={<Cable />}
            href="/integration"
            title="Integration reference"
            description="The deeplink scheme, the export file and the room invite."
          />
        </Cards>
        <p className="mt-4 text-sm text-fd-muted-foreground">
          Browse the source, report issues and contribute on{' '}
          <Link
            href="https://github.com/thepearl/notchboard"
            className="font-medium text-fd-foreground underline"
          >
            GitHub
          </Link>
          .
        </p>
      </section>
    </main>
  );
}

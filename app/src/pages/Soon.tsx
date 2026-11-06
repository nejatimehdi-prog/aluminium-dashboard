export default function Soon({ title, phase }: { title: string; phase: string }) {
  return (
    <section className="rounded-xl border border-line bg-surface p-6 text-center">
      <h2 className="mb-2 text-base font-semibold">{title}</h2>
      <p className="text-sm text-muted">این بخش در فاز {phase} ساخته می‌شود.</p>
    </section>
  );
}

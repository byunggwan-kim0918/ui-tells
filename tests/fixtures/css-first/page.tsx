// 음성 픽스처 — 세로 리듬을 py-* 한 갈래가 아니라 pt/pb/mt 로 만든다.
export default function Page() {
  return (
    <div className="bg-paper text-ink">
      <header className="pt-10 pb-7">
        <h1 className="text-h1">제목</h1>
        <p className="text-body">본문입니다.</p>
      </header>
      <section className="mt-8 grid gap-5 lg:grid-cols-12">
        <div className="min-w-0 lg:col-span-7">
          <p className="text-body">왼쪽</p>
        </div>
        <div className="min-w-0 lg:col-span-5">
          <p className="text-body">오른쪽</p>
        </div>
      </section>
      <footer className="mt-16 pt-6">
        <p className="text-body">푸터</p>
      </footer>
    </div>
  );
}

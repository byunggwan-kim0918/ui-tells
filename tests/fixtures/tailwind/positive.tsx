// 양성 픽스처 — 아래 위반이 전부 HIT로 잡혀야 한다.
// 기대 HIT: AI 보라 · transition-all · hover:scale 남용 · 기본 폰트 · 더미 slop · dark: 변형
import { Star } from 'lucide-react';

export function Slop() {
  return (
    <div className="bg-indigo-600 text-slate-50 font-inter dark:bg-slate-900">
      <p className="text-[#6366f1]">Acme Inc</p>
      <span>John Doe · 99.9% · 10,000+ users</span>
      <img src="/api/placeholder/400/300" alt="" />

      <button className="transition-all hover:scale-105">A</button>
      <button className="transition-all hover:scale-110">B</button>
      <button className="transition-all hover:scale-105">C</button>
      <button className="transition-all hover:scale-125">D</button>
      <button className="transition-all hover:scale-95">E</button>

      {/* 별점에 상태색을 빌려 쓴 경우 */}
      <span className="flex items-center text-status-done">
        <Star size={14} /> 4.5
      </span>

      {/* 아이콘 크기 한 종류만 */}
      <Star size={14} />
      <Star size={14} />
    </div>
  );
}

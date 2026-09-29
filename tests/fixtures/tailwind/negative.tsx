// 음성 픽스처 — 여기서 HIT가 나오면 오탐이다.
// 과거에 실제로 오탐을 냈던 세 가지를 고정해 둔다. 규칙을 고칠 때 이 파일이 깨지면
// 그 수정이 예전에 잡은 오탐을 되살린 것이다.

// 오탐 1: `Inter`(폰트)가 `interface`·`INTERVAL`에 매치됐다.
interface ButtonProps {
  label: string;
}
const INTERVAL = 5_000;
const printer = { interpolate: (s: string) => s };

// 오탐 2: 섹션 리듬 체크(py-8 이상)가 버튼·칩 내부 패딩 py-1~4를 셌다.
// 오탐 3: 규칙을 설명하는 주석이 그 규칙 자신에게 걸렸다.
//   예를 들어 이 줄에 transition-all 이나 hover:scale- 이라고 적어도 HIT가 되면 안 된다.
//   dark:bg-black 이라고 주석에 적는 것도 마찬가지다.
/* 블록 주석도 같다: transition-all, hover:scale-105, dark:text-white */

export default function Button({ label }: ButtonProps) {
  return (
    <button
      className="rounded-xl px-4 py-2 text-sm font-semibold tracking-[-0.01em] leading-[1.4]
                 transition-[background-color,transform] active:scale-[0.98]"
      style={{ animationDuration: `${INTERVAL}ms` }}
    >
      {printer.interpolate(label)}
    </button>
  );
}

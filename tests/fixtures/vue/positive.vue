<!-- 양성 — Vue. 템플릿엔 Tailwind 유틸, style 블록엔 순수 CSS 슬롭.
     둘 다 잡혀야 한다(Tailwind 프로젝트가 아니어도 style 블록은 css 규칙으로 잡힘). -->
<template>
  <div class="bg-indigo-600 transition-all hover:scale-105">
    <p>Acme Inc</p>
  </div>
</template>
<style scoped>
.hero { background: linear-gradient(135deg, #6366f1, #a855f7); }
.cta  { transition: all .3s ease; font-family: Inter, sans-serif; }
.cta:hover { transform: scale(1.05); }
</style>

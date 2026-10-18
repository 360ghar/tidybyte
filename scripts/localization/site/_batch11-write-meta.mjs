#!/usr/bin/env node
// Batch 11: localized <title> and <meta name="description"> for the landing
// page. Emits scripts/localization/site/site-translations/<slug>.meta.json.
//
// Budgets come from scripts/seo-audit.mjs, which measures the DECODED string
// (after &mdash; / &amp; are folded back to one character): title <= 65,
// description 110..165. Both the raw and the decoded length are checked here
// so a value passes under either reading.
//
// Run: node scripts/localization/site/_batch11-write-meta.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, "site-translations");

const TITLE_MAX = 65;
const DESC_MIN = 110;
const DESC_MAX = 165;

/** Same decoding seo-audit.mjs applies before it measures. */
const decode = (s) =>
  s
    .replace(/&amp;/g, "&")
    .replace(/&#x27;|&rsquo;/g, "'")
    .replace(/&quot;|&rdquo;|&ldquo;/g, '"')
    .replace(/&mdash;/g, "\u2014")
    .replace(/&ndash;/g, "\u2013")
    .replace(/\s+/g, " ")
    .trim();

const META = {
  ml: {
    title: "TidyByte &mdash; iPhone സ്റ്റോറേജ്, ഫോട്ടോ ക്ലീനർ ആപ്പ്",
    description:
      "TidyByte ഒരു സൗജന്യ iPhone സ്റ്റോറേജ് ക്ലീനറും ഫോട്ടോ ക്ലീനറുമാണ്: ഡ്യൂപ്ലിക്കേറ്റുകൾ, സ്ക്രീൻഷോട്ടുകൾ, വീഡിയോകൾ എന്നിവ സ്വൈപ്പ് ചെയ്ത് നീക്കൂ. 100% ഉപകരണത്തിൽ.",
  },
  es: {
    title: "TidyByte &mdash; Limpiador de almacenamiento y fotos para iPhone",
    description:
      "TidyByte es un limpiador de fotos y almacenamiento para iPhone gratis: desliza para borrar, elimina duplicados y capturas, comprime vídeos. 100% en el dispositivo.",
  },
  fr: {
    title: "TidyByte &mdash; Nettoyeur iPhone : stockage et photos",
    description:
      "TidyByte, nettoyeur de stockage et photos pour iPhone, gratuit : balayez pour supprimer, retirez doublons et captures, compressez les vidéos. 100% sur l'appareil.",
  },
  de: {
    title: "TidyByte &mdash; iPhone Speicher reinigen und Fotos aufräumen",
    description:
      "TidyByte ist ein kostenloser iPhone-Speicher- und Foto-Reiniger: Wischen löscht Ballast, Duplikate und Screenshots, Videos werden komprimiert. 100% auf dem Gerät.",
  },
  "pt-br": {
    title: "TidyByte &mdash; Limpador de Armazenamento e Fotos para iPhone",
    description:
      "TidyByte é um limpador de armazenamento e fotos para iPhone grátis: deslize para excluir lixo, remova duplicatas e capturas, comprima vídeos. 100% no dispositivo.",
  },
  it: {
    title: "TidyByte &mdash; Pulitore iPhone: spazio e foto",
    description:
      "TidyByte è un pulitore gratuito per iPhone: libera spazio, elimina foto inutili, duplicati e istantanee, e comprime i video. 100% sul dispositivo.",
  },
  ja: {
    title: "TidyByte &mdash; iPhoneのストレージ整理・写真整理アプリ",
    description:
      "TidyByteは無料のiPhone用ストレージ整理・写真整理アプリです。スワイプするだけで不要な写真や動画を削除し、重複した写真やスクリーンショットをまとめて整理し、大きな動画は圧縮して容量を節約できます。すべての処理は端末内で完結する100%オンデバイス仕様です。",
  },
  ko: {
    title: "TidyByte &mdash; iPhone 저장공간 정리·사진 삭제 앱",
    description:
      "TidyByte는 무료 iPhone 저장공간·사진 정리 앱입니다. 스와이프로 불필요한 사진과 동영상을 삭제하고, 중복 사진과 스크린샷을 정리하고, 큰 동영상은 압축해 용량을 줄일 수 있습니다. 모든 처리는 100% 기기 안에서 이루어집니다.",
  },
  "zh-hans": {
    title: "TidyByte &mdash; iPhone 存储清理与照片清理应用",
    description:
      "TidyByte 是一款免费的 iPhone 存储清理与照片清理应用：滑动即可删除无用的照片和视频，一键清理重复照片与截图，还能压缩大视频腾出空间。所有处理均在设备本地完成，100% 在设备上运行，无需联网，保护你的隐私。",
  },
  ru: {
    title: "TidyByte &mdash; Чистка памяти и фото на iPhone",
    description:
      "TidyByte &mdash; бесплатное приложение для iPhone: чистка памяти и фото, свайп для удаления мусора, дублей и скриншотов, сжатие видео. 100% на устройстве.",
  },
};

const ENGLISH = {
  title: "TidyByte \u2014 iPhone Storage Cleaner & Photo Cleaner App",
  description:
    "TidyByte is a free iPhone storage cleaner and photo cleaner: swipe to delete junk, remove duplicates and screenshots, and compress videos. 100% on-device.",
};

let failed = false;
const rows = [];

for (const [slug, value] of Object.entries(META)) {
  const rawTitle = value.title.length;
  const decTitle = decode(value.title).length;
  const rawDesc = value.description.length;
  const decDesc = decode(value.description).length;

  const problems = [];
  if (rawTitle > TITLE_MAX || decTitle > TITLE_MAX) problems.push("title too long");
  if (!value.title.startsWith("TidyByte &mdash; "))
    problems.push("title must start with TidyByte &mdash;");
  if (decDesc < DESC_MIN) problems.push(`description too short (${decDesc})`);
  if (rawDesc > DESC_MAX) problems.push(`description raw too long (${rawDesc})`);
  if (decDesc > DESC_MAX) problems.push(`description too long (${decDesc})`);
  if (value.title.includes("\u2014") || value.description.includes("\u2014"))
    problems.push("literal em dash");
  if (/&(?!(amp|mdash|ndash|#\d+|#x[0-9a-fA-F]+);)/.test(value.title + value.description))
    problems.push("bare ampersand");
  if (value.title === ENGLISH.title || value.description === ENGLISH.description)
    problems.push("left as English source");
  if (!/TidyByte/.test(value.title)) problems.push("title missing TidyByte");

  rows.push({
    slug,
    title: `${decTitle} (raw ${rawTitle})`,
    description: `${decDesc} (raw ${rawDesc})`,
    problems,
  });
  if (problems.length) failed = true;

  if (!problems.length) {
    writeFileSync(
      join(OUT, `${slug}.meta.json`),
      `${JSON.stringify({ title: value.title, description: value.description }, null, 2)}\n`,
    );
  }
}

console.log("slug        title dec(raw)   description dec(raw)   notes");
for (const r of rows) {
  console.log(
    `${r.slug.padEnd(11)} ${r.title.padEnd(18)} ${r.description.padEnd(22)} ${r.problems.join("; ")}`,
  );
}

console.log(`\nlimits: title <= ${TITLE_MAX}; description ${DESC_MIN}-${DESC_MAX}`);
console.log(failed ? "FAIL: some files not written" : `OK: ${rows.length} files written to ${OUT}`);
process.exit(failed ? 1 : 0);

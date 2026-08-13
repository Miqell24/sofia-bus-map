// ALL-CAPS Bulgarian stop names → sentence-style mixed case.
//
// The CGM feed shouts every stop name (Ж.К. ЗАПАДЕН ПАРК) while Bulgarian —
// and the OSM base map right next to the labels — writes sentence style:
// "ж.к. Западен парк", "пл. Сточна гара", "ул. Иван Вазов". Word-by-word
// Title Case would anglicize that ("Западен Парк"), so like the Athens map
// (lib/greek.mjs) we harvest a dictionary from the OSM extracts and let it
// decide the case of every known word. Unlike Greek nothing is lost in
// capitals here — the dictionary only supplies WHICH words Bulgarian keeps
// lowercase mid-name (парк, гара, мост, шосе) and which are proper names
// (Иван, Искър). Unknown words fall back to Title Case, at worst
// capitalizing a generic noun.
//
// Harvest skips the FIRST word of every OSM name: name-initial position is
// always capitalized regardless of what the word is, so it teaches nothing —
// "Гара Искър" must not outvote the lowercase "гара" of "Централна гара".

const WORD = /[А-Яа-яA-Za-z]+/g;
const HAS_LOWER = /[а-яa-z]/;
const VOWEL = /[АЕИОУЪЮЯAEIOUY]/;

// Written in capitals in normal Bulgarian text too. Vowel-less tokens (ДКЦ,
// НДК, ЖП, ПГХМБТ, roman numerals) need no listing — a Bulgarian word always
// carries a vowel — so this set holds only the vowel-carrying ones.
const ACRONYMS = new Set([
  'ОУ', 'АД', 'УМБАЛ', 'УМБАЛСМ', 'НСБАЛ', 'МБАЛ', 'СБАЛ', 'СОУ', 'СУ',
  'ЦДГ', 'ОДЗ', 'ТЕЦ', 'НПЗ', 'ВМА', 'ИСУЛ', 'БАН', 'МВР', 'ХЕИ', 'АП',
  'ЦУМ', 'НИМ', 'СТИНД', 'КАТ', 'ДАИ', 'ЗОО',
]);

// Connectives, request-stop markers and ordinal endings ("3-ТИ", "2-РА") that
// Bulgarian never capitalizes mid-name.
const LOWER_WORDS = new Set([
  'ПО', 'ЖЕЛАНИЕ', 'НА', 'ЗА', 'И', 'ОТ', 'ДО', 'ПРИ', 'ПРЕЗ', 'КЪМ',
  'ВРЕМЕННА', 'ТИ', 'ТО', 'ТА', 'РА', 'ВА', 'МА',
]);

// Dotted abbreviations, tried longest-first while peeling a token from the
// front ("Ж.К.ИВАН" → "ж.к." + "ИВАН"). Sentence-style keeps them lowercase
// even name-initial — that is how the OSM base map writes them ("ж.к.
// Надежда 1"). "Св." stays capital (church and street dedications). A single
// capital letter with a dot that matches nothing here is a person's initial
// and stays as it is ("Т. Каблешков").
const ABBR = [
  ['СВ.СВ.', 'Св.Св.'], ['СВ.', 'Св.'], ['Ж.К.', 'ж.к.'], ['В.З.', 'в.з.'],
  ['АКАД.', 'акад.'], ['ПРОФ.', 'проф.'], ['ПОЛК.', 'полк.'], ['КАП.', 'кап.'],
  ['ИНЖ.', 'инж.'], ['ГЕН.', 'ген.'], ['БУЛ.', 'бул.'], ['УЛ.', 'ул.'],
  ['КВ.', 'кв.'], ['ПЛ.', 'пл.'], ['БЛ.', 'бл.'], ['МЛ.', 'мл.'],
  ['С.', 'с.'], ['М.', 'м.'],
];

const title = (w) => w[0].toUpperCase() + w.slice(1).toLowerCase();

export function buildNameDict(osmDocs) {
  const seen = new Map(); // UPPER word → Map(spelling → count)
  for (const doc of osmDocs) {
    for (const e of doc.elements || []) {
      const name = e.tags && e.tags.name;
      if (!name || !HAS_LOWER.test(name)) continue; // caps names teach us nothing
      const words = name.match(WORD) || [];
      for (const w of words.slice(1)) { // skip the name-initial word
        if (w.length < 3) continue;
        const k = w.toUpperCase();
        let m = seen.get(k);
        if (!m) seen.set(k, (m = new Map()));
        m.set(w, (m.get(w) || 0) + 1);
      }
    }
  }
  const dict = new Map();
  for (const [k, m] of seen) {
    let best = null, bestN = -1;
    for (const [w, n] of m) if (n > bestN) { best = w; bestN = n; }
    dict.set(k, best);
  }
  return dict;
}

function word(w, dict) {
  if (!/[А-Яа-яA-Za-z]/.test(w) || /\d/.test(w)) return w; // digits, "4А"
  if (ACRONYMS.has(w)) return w;
  if (LOWER_WORDS.has(w)) return w.toLowerCase();
  if (!VOWEL.test(w)) return w; // vowel-less = acronym or initials
  if (w.length >= 3) {
    const d = dict.get(w);
    if (d) return d;
  }
  return title(w);
}

export function bulgarianTitleCase(name, dict) {
  if (!name || HAS_LOWER.test(name)) return name; // already mixed-case — leave
  let firstDone = false;
  return name.split(/(\s+|[()\-–—,«»„“”"']+)/).map((tok) => {
    if (!/[А-Яа-яA-Za-z]/.test(tok)) {
      // a leading number IS the first word ("115-ТИ ..." must keep its
      // ordinal ending lowercase: "115-ти ...")
      if (/\d/.test(tok)) firstDone = true;
      return tok; // separators, bare numbers
    }
    let out = '';
    let rest = tok;
    let abbrStart = false;
    // peel dotted abbreviations and initials off the front
    for (;;) {
      const hit = ABBR.find(([k]) => rest.startsWith(k));
      if (hit) {
        if (!out) abbrStart = hit[1][0] !== hit[1][0].toUpperCase();
        out += hit[1];
        rest = rest.slice(hit[0].length);
        continue;
      }
      const m = rest.match(/^([А-ЯA-Z])\./); // single-letter initial
      if (m) { out += m[0]; rest = rest.slice(m[0].length); continue; }
      const m2 = rest.match(/^([А-ЯA-Z]{2,})\./); // unknown dotted (ИВ., АЛ.)
      if (m2) { out += title(m2[1]) + '.'; rest = rest.slice(m2[0].length); continue; }
      break;
    }
    if (rest) out += word(rest, dict);
    if (!firstDone) {
      firstDone = true;
      // sentence style: capitalize the first regular word, but a leading
      // lowercase abbreviation (ул., ж.к., с.) stays lowercase like on the
      // base map
      if (!abbrStart) out = out.replace(/[А-Яа-яA-Za-z]/, (c) => c.toUpperCase());
    }
    return out;
  }).join('');
}

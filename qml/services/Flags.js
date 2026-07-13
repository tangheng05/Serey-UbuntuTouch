.pragma library

var COUNTRY_NAME_TO_ISO2 = {
    // A
    "afghanistan": "af", "albania": "al", "algeria": "dz", "andorra": "ad", "angola": "ao",
    "antigua and barbuda": "ag", "argentina": "ar", "armenia": "am", "australia": "au",
    "austria": "at", "azerbaijan": "az",
    // B
    "bahamas": "bs", "bahrain": "bh", "bangladesh": "bd", "barbados": "bb", "belarus": "by",
    "belgium": "be", "belize": "bz", "benin": "bj", "bhutan": "bt", "bolivia": "bo",
    "bosnia and herzegovina": "ba", "botswana": "bw", "brazil": "br", "brunei": "bn",
    "bulgaria": "bg", "burkina faso": "bf", "burundi": "bi",
    // C
    "cabo verde": "cv", "cape verde": "cv", "cambodia": "kh", "cameroon": "cm",
    "canada": "ca", "central african republic": "cf", "chad": "td", "chile": "cl",
    "china": "cn", "colombia": "co", "comoros": "km", "congo": "cg",
    "democratic republic of the congo": "cd", "dr congo": "cd",
    "costa rica": "cr", "croatia": "hr", "cuba": "cu", "cyprus": "cy",
    "czech republic": "cz", "czechia": "cz",
    // D
    "denmark": "dk", "djibouti": "dj", "dominica": "dm", "dominican republic": "do",
    // E
    "ecuador": "ec", "egypt": "eg", "el salvador": "sv", "equatorial guinea": "gq",
    "eritrea": "er", "estonia": "ee", "eswatini": "sz", "ethiopia": "et",
    // F
    "fiji": "fj", "finland": "fi", "france": "fr",
    // G
    "gabon": "ga", "gambia": "gm", "georgia": "ge", "germany": "de", "ghana": "gh",
    "greece": "gr", "grenada": "gd", "guatemala": "gt", "guinea": "gn",
    "guinea-bissau": "gw", "guyana": "gy",
    // H
    "haiti": "ht", "honduras": "hn", "hungary": "hu",
    // I
    "iceland": "is", "india": "in", "indonesia": "id", "iran": "ir", "iraq": "iq",
    "ireland": "ie", "israel": "il", "italy": "it",
    // J
    "jamaica": "jm", "japan": "jp", "jordan": "jo",
    // K
    "kazakhstan": "kz", "kenya": "ke", "kiribati": "ki", "north korea": "kp",
    "south korea": "kr", "korea": "kr", "kuwait": "kw", "kyrgyzstan": "kg",
    // L
    "laos": "la", "latvia": "lv", "lebanon": "lb", "lesotho": "ls", "liberia": "lr",
    "libya": "ly", "liechtenstein": "li", "lithuania": "lt", "luxembourg": "lu",
    // M
    "madagascar": "mg", "malawi": "mw", "malaysia": "my", "maldives": "mv", "mali": "ml",
    "malta": "mt", "marshall islands": "mh", "mauritania": "mr", "mauritius": "mu",
    "mexico": "mx", "micronesia": "fm", "moldova": "md", "monaco": "mc", "mongolia": "mn",
    "montenegro": "me", "morocco": "ma", "mozambique": "mz", "myanmar": "mm", "burma": "mm",
    // N
    "namibia": "na", "nauru": "nr", "nepal": "np", "netherlands": "nl", "nederland": "nl",
    "new zealand": "nz", "nicaragua": "ni", "niger": "ne", "nigeria": "ng",
    "north macedonia": "mk", "norway": "no",
    // O
    "oman": "om",
    // P
    "pakistan": "pk", "palau": "pw", "palestine": "ps", "panama": "pa",
    "papua new guinea": "pg", "paraguay": "py", "peru": "pe", "philippines": "ph",
    "poland": "pl", "portugal": "pt",
    // Q
    "qatar": "qa",
    // R
    "romania": "ro", "russia": "ru", "rwanda": "rw",
    // S
    "saint kitts and nevis": "kn", "saint lucia": "lc",
    "saint vincent and the grenadines": "vc", "samoa": "ws",
    "san marino": "sm", "sao tome and principe": "st", "saudi arabia": "sa",
    "senegal": "sn", "serbia": "rs", "seychelles": "sc", "sierra leone": "sl",
    "singapore": "sg", "slovakia": "sk", "slovenia": "si", "solomon islands": "sb",
    "somalia": "so", "south africa": "za", "south sudan": "ss", "spain": "es",
    "sri lanka": "lk", "sudan": "sd", "suriname": "sr", "sweden": "se",
    "switzerland": "ch", "syria": "sy",
    // T
    "taiwan": "tw", "tajikistan": "tj", "tanzania": "tz", "thailand": "th",
    "timor-leste": "tl", "east timor": "tl", "togo": "tg", "tonga": "to",
    "trinidad and tobago": "tt", "tunisia": "tn", "turkey": "tr", "turkiye": "tr",
    "turkmenistan": "tm", "tuvalu": "tv",
    // U
    "uganda": "ug", "ukraine": "ua", "united arab emirates": "ae", "uae": "ae",
    "united kingdom": "gb", "uk": "gb", "great britain": "gb", "england": "gb",
    "united states": "us", "united states of america": "us", "usa": "us",
    "america": "us", "uruguay": "uy", "uzbekistan": "uz",
    // V
    "vanuatu": "vu", "venezuela": "ve", "vietnam": "vn", "viet nam": "vn",
    // Y
    "yemen": "ye",
    // Z
    "zambia": "zm", "zimbabwe": "zw"
};

// title -> ISO2 code, mirroring fe-serey-web's getFlagCodeFromTitle: exact match
// first, then a substring match (e.g. "Serey USA", "Voetbal Nederland").
function flagCodeFromTitle(title) {
    if (!title) return null;
    var key = ("" + title).trim().toLowerCase();
    if (COUNTRY_NAME_TO_ISO2[key]) return COUNTRY_NAME_TO_ISO2[key];
    for (var name in COUNTRY_NAME_TO_ISO2) {
        if (key.indexOf(name) !== -1) return COUNTRY_NAME_TO_ISO2[name];
    }
    return null;
}

// Full flagcdn URL for a country title, or "" if the title doesn't resolve.
function flagUrl(title) {
    var code = flagCodeFromTitle(title);
    return code ? ("https://flagcdn.com/w160/" + code + ".png") : "";
}

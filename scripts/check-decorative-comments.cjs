const { readFileSync } = require("node:fs");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const ts = require("typescript");

const root = path.resolve(__dirname, "..");
const separators = "=-*#~_/─━═╍┅┄┈╌⎯";

function decorative(content) {
  const visible = [...content.trim()].filter(
    (character) => !/\s/.test(character)
  );
  if (!visible.length) return false;
  const run = /([=\-*#~_/─━═╍┅┄┈╌⎯])\1{3,}/.exec(content);
  if (!run) return false;
  const delimiters = "`'\"/|";
  const before = content[run.index - 1];
  const after = content[run.index + run[0].length];
  if (
    before &&
    after &&
    delimiters.includes(before) &&
    delimiters.includes(after)
  )
    return false;
  return (
    visible.filter((character) => separators.includes(character)).length /
      visible.length >=
    0.5
  );
}

function comments(source, extension) {
  const result = [];
  if ([".js", ".cjs", ".mjs", ".ts", ".sol", ".circom"].includes(extension)) {
    const scanner = ts.createScanner(
      ts.ScriptTarget.Latest,
      false,
      ts.LanguageVariant.Standard,
      source
    );
    for (
      let token = scanner.scan();
      token !== ts.SyntaxKind.EndOfFileToken;
      token = scanner.scan()
    ) {
      if (
        [
          ts.SyntaxKind.SingleLineCommentTrivia,
          ts.SyntaxKind.MultiLineCommentTrivia,
        ].includes(token)
      ) {
        result.push({
          offset: scanner.getTokenPos(),
          text: scanner
            .getTokenText()
            .replace(/^\/\/|^\/\*/, "")
            .replace(/\*\/$/, ""),
        });
      }
    }
  } else if (extension === ".lean") {
    let index = 0;
    while (index < source.length) {
      if (source[index] === '"') {
        index++;
        while (index < source.length && source[index] !== '"') {
          index += source[index] === "\\" ? 2 : 1;
        }
        index++;
      } else if (source.startsWith("--", index)) {
        const end = source.indexOf("\n", index);
        result.push({
          offset: index,
          text: source.slice(index + 2, end < 0 ? source.length : end),
        });
        index = end < 0 ? source.length : end;
      } else if (source.startsWith("/-", index)) {
        const start = index;
        index += 2;
        let depth = 1;
        while (index < source.length && depth) {
          if (source.startsWith("/-", index)) {
            depth++;
            index += 2;
          } else if (source.startsWith("-/", index)) {
            depth--;
            index += 2;
          } else index++;
        }
        result.push({
          offset: start,
          text: source.slice(start + 2, index - 2).replace(/^[!\*]/, ""),
        });
      } else index++;
    }
  } else {
    const pattern = extension === ".md" ? /<!--([\s\S]*?)-->/g : /^\s*#(.*)$/gm;
    for (const match of source.matchAll(pattern))
      result.push({ offset: match.index, text: match[1] });
  }
  return result;
}

function findings(source, extension) {
  const result = [];
  for (const comment of comments(source, extension)) {
    const firstLine = source.slice(0, comment.offset).split("\n").length;
    comment.text.split("\n").forEach((line, index) => {
      if (decorative(line.replace(/^\s*\*\s?/, "")))
        result.push(firstLine + index);
    });
  }
  return result;
}

if (require.main === module) {
  const files = [
    ...new Set(
      execFileSync(
        "git",
        ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        { cwd: root, encoding: "utf8" }
      )
        .split("\0")
        .filter(Boolean)
    ),
  ];
  const extensions = new Set([
    ".js",
    ".cjs",
    ".mjs",
    ".ts",
    ".sol",
    ".circom",
    ".lean",
    ".sh",
    ".toml",
    ".yml",
    ".yaml",
    ".md",
  ]);
  let count = 0;
  for (const file of files) {
    const extension = path.extname(file);
    if (!extensions.has(extension) && path.basename(file) !== "Makefile")
      continue;
    let source;
    try {
      source = readFileSync(path.join(root, file), "utf8");
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    for (const line of findings(source, extension)) {
      console.error(`${file}:${line}: remove the decorative comment`);
      count++;
    }
  }
  if (count) process.exit(1);
  console.log(
    "No decorative comments in repository-owned source and configuration."
  );
}

module.exports = { decorative, findings };

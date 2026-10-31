import 'package:flutter/material.dart';

import 'theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _orange = Color(0xFFD97757);
const _blue = Color(0xFF8AB4F8);
const _yellow = Color(0xFFE9C46A);
const _green = Color(0xFF9ED8B5);
const _purple = Color(0xFFD7A6E8);
const _red = Color(0xFFE5867A);
const _amber = Color(0xFFE5B44A);
const _teal = Color(0xFF7CC7C9);
const _grey = Color(0xFF8C857A);

String _ext(String name) {
  final l = name.toLowerCase();
  final i = l.lastIndexOf('.');
  return i <= 0 ? '' : l.substring(i + 1);
}

(IconData, Color)? _byName(String lower) {
  if (lower == '.env' || lower.startsWith('.env.')) {
    return (LucideIcons.fileKey, _amber);
  }
  if (lower.startsWith('license') ||
      lower.startsWith('licence') ||
      lower == 'copying') {
    return (LucideIcons.fileBadge, _amber);
  }
  if (lower.startsWith('readme')) return (LucideIcons.fileText, _blue);
  if (lower.startsWith('changelog')) return (LucideIcons.fileClock, _blue);
  if (lower == 'dockerfile' ||
      lower.startsWith('dockerfile.') ||
      lower.startsWith('docker-compose') ||
      lower.startsWith('compose.')) {
    return (LucideIcons.fileBox, _blue);
  }
  if (lower == 'makefile' ||
      lower == 'justfile' ||
      lower == 'procfile' ||
      lower == 'rakefile') {
    return (LucideIcons.fileTerminal, _orange);
  }
  if (lower.startsWith('.git')) return (LucideIcons.fileDiff, _orange);
  if (const {
    'package.json',
    'cargo.toml',
    'pubspec.yaml',
    'pyproject.toml',
    'go.mod',
    'gemfile',
    'composer.json',
    'build.gradle',
    'build.gradle.kts',
    'pom.xml',
    'requirements.txt',
    'setup.py',
    'deno.json',
    'bun.lockb',
  }.contains(lower)) {
    return (LucideIcons.fileBox, _green);
  }
  if (lower.endsWith('.lock') ||
      lower.endsWith('-lock.json') ||
      lower.endsWith('-lock.yaml') ||
      lower == 'go.sum') {
    return (LucideIcons.fileLock, _grey);
  }
  if (lower.startsWith('tsconfig') ||
      lower.startsWith('jsconfig') ||
      lower.contains('.config.') ||
      lower.startsWith('.eslintrc') ||
      lower.startsWith('.prettierrc') ||
      lower == '.editorconfig' ||
      lower.startsWith('.babelrc') ||
      lower == 'analysis_options.yaml' ||
      lower.startsWith('.npmrc') ||
      lower.startsWith('.nvmrc')) {
    return (LucideIcons.fileCog, _teal);
  }
  return null;
}

(IconData, Color) fileIconFor(String name) {
  final lower = name.split('/').last.toLowerCase();
  final named = _byName(lower);
  if (named != null) return named;
  return switch (_ext(lower)) {
    'rs' => (LucideIcons.fileCode, _orange),
    'swift' || 'kt' || 'kts' || 'java' || 'scala' => (
        LucideIcons.fileCode,
        _orange
      ),
    'dart' || 'go' || 'py' || 'pyi' => (LucideIcons.fileCode, _blue),
    'c' || 'h' || 'cc' || 'cpp' || 'hpp' || 'cs' || 'm' || 'mm' => (
        LucideIcons.fileCode,
        _blue
      ),
    'ts' || 'tsx' || 'mts' || 'cts' => (LucideIcons.fileCode, _blue),
    'js' || 'jsx' || 'mjs' || 'cjs' => (LucideIcons.fileCode, _yellow),
    'rb' || 'erb' || 'ex' || 'exs' || 'erl' || 'clj' => (
        LucideIcons.fileCode,
        _red
      ),
    'php' || 'lua' || 'zig' || 'nim' || 'jl' || 'r' || 'hs' || 'ml' => (
        LucideIcons.fileCode,
        _purple
      ),
    'vue' || 'svelte' || 'astro' => (LucideIcons.fileCode, _green),
    'html' || 'htm' || 'xml' || 'xhtml' => (LucideIcons.fileCode, _orange),
    'css' || 'scss' || 'sass' || 'less' || 'styl' => (
        LucideIcons.fileCode,
        _purple
      ),
    'sql' || 'prisma' || 'graphql' || 'gql' || 'proto' => (
        LucideIcons.fileCode,
        _teal
      ),
    'json' || 'jsonc' || 'json5' || 'jsonl' || 'ndjson' => (
        LucideIcons.fileBraces,
        _yellow
      ),
    'yaml' ||
    'yml' ||
    'toml' ||
    'ini' ||
    'cfg' ||
    'conf' ||
    'properties' ||
    'plist' ||
    'env' =>
      (LucideIcons.fileSliders, _green),
    'md' || 'mdx' || 'markdown' || 'rst' || 'adoc' || 'org' || 'tex' => (
        LucideIcons.fileText,
        _blue
      ),
    'txt' || 'rtf' => (LucideIcons.fileText, _grey),
    'log' => (LucideIcons.fileClock, _grey),
    'pdf' => (LucideIcons.fileText, _red),
    'doc' || 'docx' || 'odt' || 'pages' => (LucideIcons.fileText, _blue),
    'csv' || 'tsv' || 'xls' || 'xlsx' || 'ods' || 'numbers' || 'parquet' => (
        LucideIcons.fileSpreadsheet,
        _green
      ),
    'ppt' || 'pptx' || 'odp' => (LucideIcons.filePlay, _orange),
    'ipynb' => (LucideIcons.fileChartLine, _orange),
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'ico' ||
    'avif' ||
    'heic' ||
    'tif' ||
    'tiff' ||
    'psd' =>
      (LucideIcons.fileImage, _purple),
    'svg' => (LucideIcons.fileImage, _yellow),
    'fig' || 'sketch' || 'xd' => (LucideIcons.fileImage, _red),
    'mp4' || 'mov' || 'webm' || 'mkv' || 'avi' || 'm4v' => (
        LucideIcons.fileVideo,
        _red
      ),
    'mp3' || 'wav' || 'm4a' || 'flac' || 'ogg' || 'aac' || 'aiff' => (
        LucideIcons.fileMusic,
        _purple
      ),
    'zip' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' ||
    'zst' ||
    '7z' ||
    'rar' ||
    'jar' ||
    'war' =>
      (LucideIcons.fileArchive, _amber),
    'apk' || 'aab' || 'ipa' || 'dmg' || 'pkg' || 'deb' || 'rpm' || 'msi' => (
        LucideIcons.fileBox,
        _amber
      ),
    'sh' || 'bash' || 'zsh' || 'fish' || 'ps1' || 'bat' || 'cmd' || 'nu' => (
        LucideIcons.fileTerminal,
        _green
      ),
    'ttf' || 'otf' || 'woff' || 'woff2' || 'eot' => (
        LucideIcons.fileType,
        _red
      ),
    'pem' || 'crt' || 'cer' || 'p12' || 'pfx' || 'pub' || 'gpg' || 'asc' => (
        LucideIcons.fileKey,
        _amber
      ),
    'diff' || 'patch' => (LucideIcons.fileDiff, _orange),
    'db' || 'sqlite' || 'sqlite3' || 'wal' => (LucideIcons.fileStack, _teal),
    'glb' || 'gltf' || 'obj' || 'fbx' || 'stl' || 'blend' || 'usdz' => (
        LucideIcons.fileAxis3d,
        _purple
      ),
    'wasm' || 'so' || 'dylib' || 'dll' || 'exe' || 'bin' || 'o' || 'a' => (
        LucideIcons.fileDigit,
        _grey
      ),
    'lock' => (LucideIcons.fileLock, _grey),
    'csr' || 'sig' => (LucideIcons.fileSignature, _amber),
    _ => (LucideIcons.file, _grey),
  };
}

(IconData, Color) folderIconFor(String name, {bool open = false}) {
  final l = name.toLowerCase();
  return switch (l) {
    '.git' => (LucideIcons.folderGit2, _orange),
    '.github' || '.gitlab' || '.circleci' => (LucideIcons.folderGit, _grey),
    'src' ||
    'lib' ||
    'app' ||
    'source' ||
    'packages' ||
    'pkg' ||
    'internal' ||
    'cmd' ||
    'crates' ||
    'components' ||
    'modules' =>
      (LucideIcons.folderCode, _blue),
    'test' ||
    'tests' ||
    '__tests__' ||
    'spec' ||
    'specs' ||
    'e2e' ||
    'integration_test' ||
    'testdata' ||
    'fixtures' =>
      (LucideIcons.folderCheck, _green),
    'docs' || 'doc' || 'documentation' || 'wiki' || 'notes' => (
        LucideIcons.folderBookmark,
        _blue
      ),
    'node_modules' ||
    'vendor' ||
    'third_party' ||
    '.venv' ||
    'venv' ||
    '.dart_tool' ||
    'pods' =>
      (LucideIcons.folderArchive, _grey),
    'build' ||
    'dist' ||
    'out' ||
    'target' ||
    '.next' ||
    '.nuxt' ||
    '.output' ||
    'release' ||
    'bin' ||
    'obj' =>
      (LucideIcons.folderOutput, _grey),
    'config' ||
    '.config' ||
    '.vscode' ||
    '.idea' ||
    'settings' ||
    '.claude' ||
    '.cursor' =>
      (LucideIcons.folderCog, _teal),
    'scripts' || 'tools' || 'hack' || 'ci' || '.husky' => (
        LucideIcons.folderCog2,
        _green
      ),
    'assets' ||
    'public' ||
    'static' ||
    'images' ||
    'img' ||
    'icons' ||
    'media' ||
    'fonts' ||
    'res' ||
    'resources' =>
      (LucideIcons.folderHeart, _purple),
    'secrets' || 'keys' || '.ssh' || 'certs' => (LucideIcons.folderKey, _amber),
    'tmp' || 'temp' || 'cache' || '.cache' || 'logs' => (
        LucideIcons.folderClock,
        _grey
      ),
    'android' || 'ios' || 'macos' || 'linux' || 'windows' || 'web' => (
        LucideIcons.folderRoot,
        _green
      ),
    'migrations' || 'db' || 'data' || 'database' => (
        LucideIcons.folderSync,
        _teal
      ),
    'examples' || 'samples' || 'demo' || 'templates' => (
        LucideIcons.folderKanban,
        _yellow
      ),
    _ => (open ? LucideIcons.folderOpen : LucideIcons.folder, _grey),
  };
}

/// Short label and colour for source files, drawn as a badge so each language
/// reads at a glance without shipping any icon assets.
(String, Color)? fileBadgeFor(String name) {
  final lower = name.split('/').last.toLowerCase();
  if (_byName(lower) != null) return null;
  return switch (_ext(lower)) {
    'rs' => ('RS', _orange),
    'go' => ('GO', _teal),
    'py' || 'pyi' => ('PY', _blue),
    'js' || 'mjs' || 'cjs' => ('JS', _yellow),
    'jsx' => ('JSX', _yellow),
    'ts' || 'mts' || 'cts' => ('TS', _blue),
    'tsx' => ('TSX', _blue),
    'dart' => ('DT', _teal),
    'kt' || 'kts' => ('KT', _purple),
    'swift' => ('SW', _orange),
    'java' => ('JV', _red),
    'scala' => ('SC', _red),
    'c' => ('C', _blue),
    'h' || 'hpp' => ('H', _purple),
    'cc' || 'cpp' || 'cxx' => ('C++', _blue),
    'cs' => ('C#', _green),
    'm' || 'mm' => ('OC', _blue),
    'rb' || 'erb' => ('RB', _red),
    'php' => ('PHP', _purple),
    'lua' => ('LU', _blue),
    'zig' => ('ZG', _amber),
    'nim' => ('NM', _yellow),
    'ex' || 'exs' => ('EX', _purple),
    'erl' => ('ER', _red),
    'clj' => ('CJ', _green),
    'hs' => ('HS', _purple),
    'ml' => ('ML', _orange),
    'jl' => ('JL', _purple),
    'r' => ('R', _blue),
    'sh' || 'bash' || 'zsh' || 'fish' => ('SH', _green),
    'ps1' => ('PS', _blue),
    'sql' => ('SQL', _teal),
    'prisma' => ('PR', _teal),
    'graphql' || 'gql' => ('GQ', _red),
    'proto' => ('PB', _teal),
    'html' || 'htm' => ('<>', _orange),
    'xml' => ('XML', _orange),
    'css' => ('CSS', _blue),
    'scss' || 'sass' => ('SC', _red),
    'less' => ('LS', _blue),
    'vue' => ('VUE', _green),
    'svelte' => ('SV', _orange),
    'astro' => ('AS', _purple),
    'json' || 'jsonc' || 'json5' => ('{}', _yellow),
    'yaml' || 'yml' => ('YML', _red),
    'toml' => ('TML', _amber),
    'md' || 'mdx' || 'markdown' => ('MD', _blue),
    'tf' || 'hcl' => ('TF', _purple),
    'sol' => ('SOL', _grey),
    'wasm' || 'wat' => ('WA', _purple),
    _ => null,
  };
}

class FileGlyph extends StatelessWidget {
  const FileGlyph(this.name,
      {super.key, this.isDir = false, this.open = false, this.size = 14});
  final String name;
  final bool isDir;
  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!isDir) {
      final badge = fileBadgeFor(name);
      if (badge != null) {
        final (label, color) = badge;
        final box = size + 2;
        return Container(
          width: box,
          height: box,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(box * 0.26),
          ),
          child: Text(label,
              maxLines: 1,
              style: mono(label.length > 2 ? box * 0.36 : box * 0.46,
                  weight: W.strong, height: 1, spacing: -0.3, color: color)),
        );
      }
    }
    final (icon, color) =
        isDir ? folderIconFor(name, open: open) : fileIconFor(name);
    return Icon(icon, size: size, color: color);
  }
}

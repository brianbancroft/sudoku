export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>
    body { margin: 0; font-family: Palatino, Georgia, serif; background: #F6E4EC; color: #3A2430; }
    main { max-width: 760px; margin: 0 auto; padding: 32px 20px 64px; }
    a { color: #8E1E4A; }
    h1 { font-weight: 500; }
    form, .card { background: #FFF6F9; border: 1px solid #E7C9D4; border-radius: 18px; padding: 16px; margin: 12px 0; }
    label { display: block; margin: 10px 0 4px; font-family: sans-serif; font-size: 14px; }
    input, textarea, select { width: 100%; box-sizing: border-box; padding: 10px; border-radius: 12px; border: 1px solid #E7C9D4; font: inherit; }
    button, .button { background: #8E1E4A; color: #FFF7FA; border: 0; border-radius: 14px; padding: 12px 16px; font: 600 16px sans-serif; }
    table { width: 100%; border-collapse: collapse; background: #FFF6F9; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid #E7C9D4; font-family: sans-serif; font-size: 14px; }
    .row { display: flex; gap: 12px; align-items: center; justify-content: space-between; }
  </style>
</head>
<body><main>${body}</main></body>
</html>`;
}

export function csrfField(token: string): string {
  return `<input type="hidden" name="csrf" value="${escapeHtml(token)}" />`;
}

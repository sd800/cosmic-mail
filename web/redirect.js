// Normalize website entry aliases before rendering; local HTML stays directly openable.
(() => {
  if (location.protocol !== 'https:' && location.protocol !== 'http:') return;
  const url = new URL(location.href);
  const path = url.pathname.replace(/\/index(?:\.html|\/(?:index\.html)?)?$/, '/');
  if (path === url.pathname) return;
  url.pathname = path;
  location.replace(url.href);
})();

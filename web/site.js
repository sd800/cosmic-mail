(() => {
  'use strict';
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  const status = document.getElementById('copy-status');
  let statusTimer;
  function select(tab, focus = false) {
    for (const item of tabs) {
      const selected = item === tab;
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
    }
    clearTimeout(statusTimer);
    status.textContent = '';
    if (focus) tab.focus({preventScroll: true});
  }
  for (const [index, tab] of tabs.entries()) {
    tab.addEventListener('click', () => select(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault();
      select(tabs[next], true);
    });
  }
  document.querySelector('[data-show-capture]').addEventListener('click', () => {
    const tab = document.getElementById('tab-link');
    select(tab, true);
    document.querySelector('.product-stage').scrollIntoView({block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'});
  });
  document.querySelector('a[href="#file-formats"]').addEventListener('click', () => {
    document.getElementById('file-formats').open = true;
  });
  if (location.hash === '#file-formats') document.getElementById('file-formats').open = true;

  const examples = {
    details: 'To: hello@example.org\nSubject: A quick question\n\nHello! I’d love to know a little more.',
    link: 'mailto:hello@example.org?subject=A%20quick%20question&body=Hello!%20I%E2%80%99d%20love%20to%20know%20a%20little%20more.'
  };
  async function copy(text) {
    if (navigator.clipboard?.writeText) {
      try { await navigator.clipboard.writeText(text); return true; } catch { /* Local-file environments may use the selection path. */ }
    }
    const field = document.createElement('textarea');
    field.className = 'copy-buffer';
    field.value = text;
    field.setAttribute('readonly', '');
    const active = document.activeElement;
    document.body.append(field);
    field.select();
    let copied = false;
    try { copied = document.execCommand('copy'); } catch { /* Keep failure local to this example. */ }
    field.remove();
    active?.focus({preventScroll: true});
    return copied;
  }
  for (const button of document.querySelectorAll('[data-copy]')) button.addEventListener('click', async () => {
    if (button.disabled) return;
    button.disabled = true;
    const copied = await copy(examples[button.dataset.copy]);
    button.disabled = false;
    if (document.getElementById('preview-link').hidden) return;
    status.textContent = copied ? 'Copied.' : 'Select the example text to copy it.';
    clearTimeout(statusTimer);
    statusTimer = setTimeout(() => { status.textContent = ''; }, 2500);
  });
})();

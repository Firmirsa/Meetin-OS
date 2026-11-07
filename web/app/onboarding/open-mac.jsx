'use client';

export default function OpenMacIntegrations({label}) {
  function open() {
    const invite = new URL('meetinos://connect');
    invite.searchParams.set('server', window.location.origin);
    window.location.assign(invite.href);
  }

  return <button className="mt-btn mt-btn--ghost" type="button" onClick={open}>{label}</button>;
}

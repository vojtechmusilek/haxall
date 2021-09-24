//
// Copyright (c) 2015, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   26 Dec 2015  Brian Frank  Creation
//   22 Sep 2021  Brian Frank  Port to Haxall
//

using concurrent
using inet
using web
using wisp
using haystack
using hx

**
** HTTP service handling
**
const class HttpLib : HxLib, HxHttpService
{
  WispService wisp() { wispRef.val }
  private const AtomicRef wispRef := AtomicRef(null)

  ** Publish the HxHttpService
  override HxService[] services() { [this] }

  ** Settings record
  override HttpSettings rec() { super.rec }

  ** Root WebMod instance
  override WebMod? root(Bool checked := true) { rootRef.val }

  ** Root WebMod instance to use when Wisp is launched
  const AtomicRef rootRef := AtomicRef(HttpRootMod(this))

  ** Public HTTP or HTTPS URI of this host.  This is always
  ** an absolute URI such 'https://acme.com/'
  override Uri siteUri()
  {
    settings := this.rec
    if (settings.siteUri != null && !settings.siteUri.toStr.isEmpty)
      return settings.siteUri.plusSlash

    host := IpAddr.local.hostname
    if (settings.httpsEnabled)
      return `https://${host}:${settings.httpsPort}/`
    else
      return `http://${host}:${settings.httpPort}/`
  }

  ** URI on this host to the Haystack HTTP API.  This is always
  ** a host relative URI which end withs a slash such '/api/'.
  override Uri apiUri() { `/api/` }

  ** Ready callback
  override Void onReady()
  {
    settings      := this.rec
    addr          := settings.addr?.trimToNull == null ? null : IpAddr(settings.addr)
    httpsEnabled  := settings.httpsEnabled
    httpsKeyStore := rt.crypto.httpsKey(false)
    socketConfig  := SocketConfig.cur.copy { it.keystore = httpsKeyStore }

    if (httpsEnabled && httpsKeyStore == null)
    {
      httpsEnabled = false
      log.err("Failed to obtain entry with alias 'https' from the keystore. Disabling HTTPS")
    }

    wisp := WispService
    {
      it.httpPort     = settings.httpPort
      it.httpsPort    = httpsEnabled ? settings.httpsPort : null
      it.addr         = addr
      it.root         = this.root
      it.errMod       = it.errMod is WispDefaultErrMod ? HttpErrMod(this) : it.errMod
      it.socketConfig = socketConfig
    }
    wispRef.val = wisp
    wisp.start
  }

  ** Unready callback
  override Void onUnready()
  {
    wisp.stop
  }
}

**************************************************************************
** HttpRootMod
**************************************************************************

internal const class HttpRootMod : WebMod
{
  new make(HttpLib lib) { this.rt = lib.rt; this.lib = lib }

  const HxRuntime rt
  const HttpLib lib

  override Void onService()
  {
    req := this.req
    res := this.res
    // echo("-- $req.method $req.uri")

    // use first level of my path to lookup lib
    libName := req.modRel.path.first ?: ""

    // if name is empty, redirect
    if (libName.isEmpty)
    {
      // redirect to shell as the built-in UI
      return res.redirect(`/shell`)
    }

    // lookup lib as hxFoo and foo
    lib := rt.lib("hx"+libName.capitalize, false)
    if (lib == null) lib = rt.lib(libName, false)
    if (lib == null) return res.sendErr(404)

    // check if it supports HxLibWeb
    libWeb := lib.web
    if (libWeb.isUnsupported) return res.sendErr(404)

    // dispatch to lib's HxLibWeb instance
    req.mod = libWeb
    req.modBase = req.modBase + `$libName/`
    libWeb.onService
  }
}

**************************************************************************
** HttpErrMod
**************************************************************************

internal const class HttpErrMod : WebMod
{
  new make(HttpLib lib) { this.lib = lib }

  const HttpLib lib

  override Void onService()
  {
    err := (Err)req.stash["err"]
    errTrace := lib.rec.disableErrTrace ? err.toStr : err.traceToStr

    res.headers["Content-Type"] = "text/html; charset=utf-8"
    res.out.html
     .head
       .title.w("$res.statusCode INTERNAL SERVER ERROR").titleEnd
     .headEnd
     .body
       .h1.w("$res.statusCode INTERNAL SERVER ERROR").h1End
       .pre.esc(errTrace).preEnd
     .bodyEnd
     .htmlEnd
  }
}




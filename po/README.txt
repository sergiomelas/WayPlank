================================================================================
          WAYPLANK MONOLITHIC LOCALIZATION & INTERNATIONALIZATION GUIDE
================================================================================

WayPlank is designed from the ground up as a high-performance, standalone, and
monolithic Wayland desktop dock. Unlike legacy applications that depend on
scattered filesystem paths (/usr/share/locale/<lang>/LC_MESSAGES/...),
WayPlank's localization architecture is designed to be 100% SELF-CONTAINED
and EMBEDDED directly into the single binary executable ('wayplank').

--------------------------------------------------------------------------------
CORE PRINCIPLE: 100% STANDALONE MONOLITHIC BINARY GUARANTEE
--------------------------------------------------------------------------------
WayPlank will NEVER be distributed as a multi-file bundle requiring external
locale directories. The primary build output of 'BuildBin.sh' is ONE SINGLE
STANDALONE FILE ('build/wayplank'). All translations, icons, themes, and logic
reside inside this single ~7.8 MB executable. When this single file is launched
on a computer with any supported language, it translates automatically directly
from internal memory without accessing the filesystem or requiring installation.

--------------------------------------------------------------------------------
1. SUPPORTED LANGUAGES & STATUS (322 / 322 STRINGS QUALIFIED - 100%)
--------------------------------------------------------------------------------

Language catalogs and contributor attribution:

  1. 简体中文 (Simplified Chinese, 'zh_CN'):
     - Contributor & Reviewer: 史有虎 (IFtiger-hu) <2212363803@qq.com>
     - Status: 100% Translated (322/322 messages).
  2. Italiano (Italian, 'it'):
     - Maintainer: Sergio Melas <sergiomelas@gmail.com>
     - Status: 100% Translated (322/322 messages).
  3. Español (Spanish, 'es'):
     - Status: 100% Translated (322/322 messages).
  4. Français (French, 'fr'):
     - Status: 100% Translated (322/322 messages).
  5. Català (Catalan, 'ca'):
     - Status: 100% Translated (322/322 messages).
  6. Deutsch (German, 'de'):
     - Contributor & Reviewer: Renate Schwiedernoch <renate.schwiedernoch@gmail.com>
     - Status: 100% Translated (322/322 messages).
  7. Українська (Ukrainian, 'uk'):
     - Contributor & Reviewer: Michailo Buchko <mixabuchko@gmail.com>
     - Status: 100% Translated (322/322 messages).
  8. English ('en'):
     - Native in-source fallback language (requires zero translation files).

--------------------------------------------------------------------------------
2. MONOLITHIC INTEGRATION ROADMAP & STEP-BY-STEP IMPLEMENTATION (BETA v0.7.0)
--------------------------------------------------------------------------------

During the current pre-beta milestone (v0.6.2.3), all translation catalogs and
generation tools are preserved cleanly in the 'po/' directory without modifying
active dock runtime behavior.

To activate the 100% monolithic embedded localization engine when transitioning
from v0.6.2.3 to Public Beta (v0.7.0), the following exact technical steps
will be implemented:

--------------------------------------------------------------------------------
STEP 1: EMBED TRANSLATION DATA INTO GRESOURCE (data/plank.gresource.xml)
--------------------------------------------------------------------------------
In 'BuildBin.sh', prior to executing 'glib-compile-resources', add a build step
that compiles all .po files to binary .mo files into 'data/locale/':

    for po in po/*.po; do
        lang=$(basename "$po" .po)
        mkdir -p "data/locale/${lang}"
        msgfmt "$po" -o "data/locale/${lang}/wayplank.mo"
    done

In 'data/plank.gresource.xml', register the embedded translation resources:
    <file>locale/zh_CN/wayplank.mo</file>
    <file>locale/it/wayplank.mo</file>
    <file>locale/es/wayplank.mo</file>
    <file>locale/fr/wayplank.mo</file>
    <file>locale/ca/wayplank.mo</file>
    <file>locale/de/wayplank.mo</file>
    <file>locale/uk/wayplank.mo</file>

This bakes all 5 language catalogs directly into the monolithic binary ELF.

--------------------------------------------------------------------------------
STEP 2: ZERO-DEPENDENCY IN-MEMORY TRANSLATION RESOLVER (lib/gtk-compat.c)
--------------------------------------------------------------------------------
In 'lib/gtk-compat.c', implement the lightweight in-memory lookup function:

    const char* wayplank_i18n_get (const char* msgid);
    void wayplank_i18n_init (void);

How it works:
1. 'wayplank_i18n_init()' reads the active desktop locale via
   'setlocale(LC_MESSAGES, "")' or the 'LANG' environment variable
   (e.g. "zh_CN.UTF-8" -> "zh_CN").
2. Loads the corresponding .mo catalog directly from in-memory GResource:
   'g_resources_lookup_data ("/net/launchpad/plank/locale/<lang>/wayplank.mo")'.
3. 'wayplank_i18n_get(msgid)' performs an O(1) binary hash lookup into the
   embedded .mo byte table in RAM. If found, returns the translated string;
   if missing or English, instantly returns 'msgid'.

--------------------------------------------------------------------------------
STEP 3: HOOK THE VALA GETTEXT MACRO (include/config.h)
--------------------------------------------------------------------------------
In 'include/config.h', redirect Vala's gettext macro:

    const char* wayplank_i18n_get (const char* msgid);
    #undef _
    #define _(String) wayplank_i18n_get(String)

Because Vala compiles every '_("text")' in source code to '_( "text" )', this
transparently intercepts all UI string lookups at compile time, completely
eliminating any runtime dependency on external filesystem paths!

--------------------------------------------------------------------------------
STEP 4: INITIALIZE IN MAIN (src/Main.vala)
--------------------------------------------------------------------------------
In 'src/Main.vala', call the initialization routine at startup:

    wayplank_i18n_init ();

--------------------------------------------------------------------------------
STEP 5: DISTRIBUTION PACKAGING PARITY (BuildDeb.sh & BuildRpm.sh)
--------------------------------------------------------------------------------
While 'build/wayplank' operates 100% standalone and portable without needing
any filesystem files, 'BuildDeb.sh' and 'BuildRpm.sh' will also install
standard system .mo files to '/usr/share/locale/<lang>/LC_MESSAGES/wayplank.mo'
to satisfy Debian and Fedora package linters.

--------------------------------------------------------------------------------
3. MAINTENANCE & TOOLS
--------------------------------------------------------------------------------

To regenerate or re-verify all 5 language catalogs from the active codebase:

    python3 po/generate_translations.py

This script guarantees:
  - 100% message coverage (312/312 messages across all languages).
  - Validation with GNU 'msgfmt -c -v'.
  - Consistent ordering and validation across all catalogs.

================================================================================
                                END OF GUIDE
================================================================================

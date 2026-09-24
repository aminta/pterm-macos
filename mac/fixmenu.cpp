// macOS build of PTerm 6.0.4 for Apple Silicon and Intel.
//
// PtermApp::OnInit calls fixmenu() on the Mac.  Its source (fixmac.m in
// the original build) is not part of the published PTerm source kit.
// wxWidgets 3.2 sets up the macOS application menu by itself, so an
// empty implementation is used.  (Altered source version, see
// pterm-6.0.4/pterm-license.txt.)
extern "C" void fixmenu (void)
{
}

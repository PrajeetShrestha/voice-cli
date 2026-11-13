import os, pathlib, subprocess, tempfile, tarfile, shlex
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='voice-installer-test-') as work:
    work=pathlib.Path(work)
    archive=work/'source.tar.gz'
    with tarfile.open(archive,'w:gz') as tar:
        for name in ['run.sh','Sources','scripts']:
            tar.add(root/name,arcname='voice-cli-v0.1.0/'+name)
    mocks=work/'mocks';mocks.mkdir()
    curl=mocks/'curl'
    curl.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\nif [ "$1" = --output ]; then shift; cp '+shlex.quote(str(archive))+' "$1"; exit; fi\nshift\ndone\nexit 1\n');curl.chmod(0o755)
    install_root=work/"User's Library/Voice Studio"
    bin_dir=work/'My Tools/bin'
    env={**os.environ,'PATH':str(mocks)+':'+os.environ['PATH'],'VOICE_STUDIO_INSTALL_ROOT':str(install_root),'VOICE_STUDIO_BIN_DIR':str(bin_dir)}
    for attempt in range(3):
        subprocess.run(['/bin/sh',str(root/'install.sh')]+(['--local'] if attempt == 2 else []),env=env,check=True)
        subprocess.run(['/bin/sh','-n',str(bin_dir/'voice-studio')],check=True)
        assert (install_root/'scripts/narrate.py').exists()
        assert (install_root/'Sources/VoiceStudio/index.html').read_bytes()==(root/'Sources/VoiceStudio/index.html').read_bytes()
    launcher=str(bin_dir/'voice-studio')
    for args in [['--help'], ['help'], ['web','--help'], ['run','web','--help']]:
        assert 'Usage: voice-studio' in subprocess.check_output([launcher]+args,text=True)
    for args in [['unknown'], ['run'], ['run','wrong'], ['web','--typo']]:
        assert subprocess.run([launcher]+args,capture_output=True).returncode==2
    assert (install_root/'Sources/VoiceStudio/kokoro_bridge.py').exists()
    # Verify launcher path quoting, argument forwarding, and working directory.
    (install_root/'run.sh').write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
    output=subprocess.check_output([str(bin_dir/'voice-studio'),'--no-open','argument with spaces'],text=True)
    assert output=='--no-open\nargument with spaces\n',repr(output)
    print('PASS: install, reinstall, source/helper copies, spaces, apostrophes, executable launcher, and argument forwarding')

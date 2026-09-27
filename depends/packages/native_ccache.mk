package=native_ccache
$(package)_version=3.3.1
$(package)_download_path=https://github.com/ccache/ccache/releases/download/v$($(package)_version)
$(package)_file_name=ccache-$($(package)_version).tar.bz2
$(package)_sha256_hash=cb6e4bafbb19ba0a2ec43386b123a5f92a20e1e3384c071d5d13e0cb3c84bf73

# The generic fetch helper tries PRIORITY_DOWNLOAD_PATH first. That mirror has
# served truncated ccache responses to GitHub Actions, so fetch this pinned
# release directly from ccache's official GitHub release instead.
define $(package)_fetch_cmds
  (test -f $($(package)_source_dir)/$($(package)_file_name) || \
    (mkdir -p $($(package)_download_dir) && echo Fetching $(package)... && \
    $(build_DOWNLOAD) "$($(package)_download_dir)/$($(package)_file_name).temp" "$($(package)_download_path)/$($(package)_download_file)" && \
    echo "$($(package)_sha256_hash)  $($(package)_download_dir)/$($(package)_file_name).temp" > $($(package)_download_dir)/.$($(package)_file_name).hash && \
    $(build_SHA256SUM) -c $($(package)_download_dir)/.$($(package)_file_name).hash && \
    mv $($(package)_download_dir)/$($(package)_file_name).temp $($(package)_source_dir)/$($(package)_file_name) && \
    rm -rf $($(package)_download_dir)))
endef

define $(package)_set_vars
$(package)_config_opts=
endef

define $(package)_config_cmds
  $($(package)_autoconf)
endef

define $(package)_build_cmds
  $(MAKE)
endef

define $(package)_stage_cmds
  $(MAKE) DESTDIR=$($(package)_staging_dir) install
endef

define $(package)_postprocess_cmds
  rm -rf lib include
endef

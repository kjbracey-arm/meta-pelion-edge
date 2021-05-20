# OSTree deployment
inherit features_check

REQUIRED_DISTRO_FEATURES = "usrmerge"

OSTREE_ROOTFS ??= "${WORKDIR}/ostree-rootfs"
OSTREE_COMMIT_SUBJECT ??= "Commit-id: ${IMAGE_NAME}"
OSTREE_COMMIT_BODY ??= ""
OSTREE_COMMIT_VERSION ??= "${DISTRO_VERSION}"
OSTREE_UPDATE_SUMMARY ??= "0"

BUILD_OSTREE_TARBALL ??= "1"

SYSTEMD_USED = "${@oe.utils.ifelse(d.getVar('VIRTUAL-RUNTIME_init_manager') == 'systemd', 'true', '')}"

IMAGE_CMD_TAR = "tar --xattrs --xattrs-include=*"
CONVERSION_CMD_tar = "touch ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.${type}; ${IMAGE_CMD_TAR} --numeric-owner -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.${type}.tar -C ${TAR_IMAGE_ROOTFS} . || [ $? -eq 1 ]"
CONVERSIONTYPES_append = " tar"

TAR_IMAGE_ROOTFS_task-image-ostree = "${OSTREE_ROOTFS}"

python prepare_ostree_rootfs() {
    import oe.path
    import shutil

    ostree_rootfs = d.getVar("OSTREE_ROOTFS")
    if os.path.lexists(ostree_rootfs):
        bb.utils.remove(ostree_rootfs, True)

    # Copy required as we change permissions on some files.
    image_rootfs = d.getVar("IMAGE_ROOTFS")
    oe.path.copyhardlinktree(image_rootfs, ostree_rootfs)
}

do_image_ostree[dirs] = "${OSTREE_ROOTFS}"
do_image_ostree[prefuncs] += "prepare_ostree_rootfs"
do_image_ostree[depends] = "coreutils-native:do_populate_sysroot virtual/kernel:do_deploy ${INITRAMFS_IMAGE}:do_image_complete"
IMAGE_CMD_ostree () {
    for d in var/*; do
      if [ "${d}" != "var/local" ]; then
        rm -rf ${d}
      fi
    done

    # Create sysroot directory to which physical sysroot will be mounted
    mkdir sysroot
    ln -sf sysroot/ostree ostree

    mkdir -p usr/rootdirs

    mv etc usr/

    if [ -n "${SYSTEMD_USED}" ]; then
        mkdir -p usr/etc/tmpfiles.d
        tmpfiles_conf=usr/etc/tmpfiles.d/00ostree-tmpfiles.conf
        echo "d /var/rootdirs 0755 root root -" >>${tmpfiles_conf}
    else
        mkdir -p usr/etc/init.d
        tmpfiles_conf=usr/etc/init.d/tmpfiles.sh
        echo '#!/bin/sh' > ${tmpfiles_conf}
        echo "mkdir -p /var/rootdirs; chmod 755 /var/rootdirs" >> ${tmpfiles_conf}

        ln -s ../init.d/tmpfiles.sh usr/etc/rcS.d/S20tmpfiles.sh
    fi

    # Preserve OSTREE_BRANCHNAME for future information
    mkdir -p usr/share/sota/
    echo -n "${OSTREE_BRANCHNAME}" > usr/share/sota/branchname

    # home directories get copied from the OE root later to the final sysroot
    # Create a symlink to var/rootdirs/home to make sure the OSTree deployment
    # redirects /home to /var/rootdirs/home.
    rm -rf home/
    ln -sf var/rootdirs/home home

    # Move persistent directories to /var
    dirs="opt mnt media srv"

    for dir in ${dirs}; do
        if [ -d ${dir} ] && [ ! -L ${dir} ]; then
            if [ "$(ls -A $dir)" ]; then
                bbwarn "Data in /$dir directory is not preserved by OSTree. Consider moving it under /usr"
            fi
            rm -rf ${dir}
        fi

        if [ -n "${SYSTEMD_USED}" ]; then
            echo "d /var/rootdirs/${dir} 0755 root root -" >>${tmpfiles_conf}
        else
            echo "mkdir -p /var/rootdirs/${dir}; chmod 755 /var/rootdirs/${dir}" >>${tmpfiles_conf}
        fi
        ln -sf var/rootdirs/${dir} ${dir}
    done

    if [ -d root ] && [ ! -L root ]; then
        if [ "$(ls -A root)" ]; then
            bbfatal "Data in /root directory is not preserved by OSTree."
        fi

        if [ -n "${SYSTEMD_USED}" ]; then
            echo "d /var/roothome 0700 root root -" >>${tmpfiles_conf}
        else
            echo "mkdir -p /var/roothome; chmod 700 /var/roothome" >>${tmpfiles_conf}
        fi

        rm -rf root
        ln -sf var/roothome root
    fi

    if [ -d usr/local ] && [ ! -L usr/local ]; then
        if [ "$(ls -A usr/local)" ]; then
            bbfatal "Data in /usr/local directory is not preserved by OSTree."
        fi
        rm -rf usr/local
    fi

    if [ -n "${SYSTEMD_USED}" ]; then
        echo "d /var/usrlocal 0755 root root -" >>${tmpfiles_conf}
    else
        echo "mkdir -p /var/usrlocal; chmod 755 /var/usrlocal" >>${tmpfiles_conf}
    fi

    dirs="bin etc games include lib man sbin share src"

    for dir in ${dirs}; do
        if [ -n "${SYSTEMD_USED}" ]; then
            echo "d /var/usrlocal/${dir} 0755 root root -" >>${tmpfiles_conf}
        else
            echo "mkdir -p /var/usrlocal/${dir}; chmod 755 /var/usrlocal/${dir}" >>${tmpfiles_conf}
        fi
    done

    ln -sf ../var/usrlocal usr/local

    # Copy image manifest
    cat ${IMAGE_MANIFEST} | cut -d " " -f1,3 > usr/package.manifest
}

prepare_ostree_area() {
    bbwarn "Preparing the ostree repo area"
    if [ ! -d ${OSTREE_REPO} ]; then
        git clone ${OSTREE_REPO_GIT} ${OSTREE_REPO}
    else
        cd ${OSTREE_REPO}
        git status
        git pull || true
    fi
}

IMAGE_TYPEDEP_ostreecommit = "ostree"
do_image_ostreecommit[depends] += "ostree-native:do_populate_sysroot"
do_image_ostreecommit[prefuncs] += "prepare_ostree_area"
do_image_ostreecommit[lockfiles] += "${OSTREE_REPO}/ostree.lock"
IMAGE_CMD_ostreecommit () {
    bbwarn "Using meta-pelion-edge version of do_image_ostreecommit"
    if ! ostree --repo=${OSTREE_REPO} refs 2>&1 > /dev/null; then
        ostree --repo=${OSTREE_REPO} init --mode=archive-z2
    fi

    # Commit the result
    ostree_target_hash=$(ostree --repo=${OSTREE_REPO} commit \
           --tree=dir=${OSTREE_ROOTFS} \
           --skip-if-unchanged \
           --branch=${OSTREE_BRANCHNAME} \
           --subject="${OSTREE_COMMIT_SUBJECT}" \
           --body="${OSTREE_COMMIT_BODY}" \
           --add-metadata-string=version="${OSTREE_COMMIT_VERSION}" \
           ${EXTRA_OSTREE_COMMIT})

    echo $ostree_target_hash > ${WORKDIR}/ostree_manifest

    if [ ${@ oe.types.boolean('${OSTREE_UPDATE_SUMMARY}')} = True ]; then
        ostree --repo=${OSTREE_REPO} summary -u
    fi
}

IMAGE_TYPEDEP_ostreepush = "ostreecommit"
do_image_ostreepush[depends] += "aktualizr-native:do_populate_sysroot ca-certificates-native:do_populate_sysroot"
IMAGE_CMD_ostreepush () {
    bbwarn "Using meta-pelion-edge version of do_image_ostreepush"
    cd ${OSTREE_REPO}
    touch refs/remotes/.gitignore
    ostree_target_hash=$(cat ${WORKDIR}/ostree_manifest)
    git commit -a -m "${ostree_target_hash}"
    git push
}

IMAGE_TYPEDEP_garagesign = "ostreepush"
do_image_garagesign[depends] += "unzip-native:do_populate_sysroot"
# This lock solves OTA-1866, which is that removing GARAGE_SIGN_REPO while using
# garage-sign simultaneously for two images often causes problems.
do_image_garagesign[lockfiles] += "${DEPLOY_DIR_IMAGE}/garagesign.lock"
IMAGE_CMD_garagesign () {
    bbwarn "Using meta-pelion-edge version of do_image_garagesign"
}

IMAGE_TYPEDEP_garagecheck = "garagesign"
IMAGE_CMD_garagecheck () {
    bbwarn "Using meta-pelion-edge version of do_image_garagecheck"
}
# vim:set ts=4 sw=4 sts=4 expandtab:

FROM fedora:40@sha256:3c86d25fef9d2001712bc3d9b091fc40cf04be4767e48f1aa3b785bf58d300ed
RUN dnf install -y python3 libxcrypt-compat libstdc++ libgcc libX11 libXcursor \
    libXi libXrandr libxcb libxkbcommon libxkbcommon-x11 libwayland-client libwayland-cursor \
    xorg-x11-server-Xvfb xorg-x11-xauth desktop-file-utils findutils \
    && dnf clean all
WORKDIR /tmp

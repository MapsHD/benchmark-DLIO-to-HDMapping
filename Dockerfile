FROM ubuntu:20.04

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg2 lsb-release software-properties-common \
    build-essential git cmake \
    python3-pip \
    libceres-dev libeigen3-dev \
    libpcl-dev \
    nlohmann-json3-dev \
    tmux \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros1.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-desktop-full \
    python3-rosdep \
    python3-catkin-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone https://github.com/Livox-SDK/Livox-SDK.git && \
    cd Livox-SDK && \
    rm -rf build && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install

WORKDIR /ros_ws

COPY ./src ./src

# Canonical bag: the cloud has both `time` (float32 s, offset 20) and `t` (uint32
# ns, offset 24). dlio::Point keeps t/time/timestamp in one union, and
# pcl::fromROSMsg copies fields in offset order, so the union ends up holding `t`.
# Sensor detection, though, stops at the first matching field, `time`, and picks
# VELODYNE, which reads those ns bits as a float (~1e-37 s): deskew is silently
# off. Pick OUSTER (`t`) whenever the cloud has `t`. Fails the build if the line
# changes.
RUN f=src/direct_lidar_inertial_odometry/src/dlio/odom.cc && \
    grep -q '    } else if (field.name == "time") {' $f && \
    sed -i 's|    } else if (field.name == "time") {|    } else if (field.name == "time" \&\& std::none_of(pc->fields.begin(), pc->fields.end(), [](const sensor_msgs::PointField\& f) { return f.name == "t"; })) {|' $f && \
    [ "$(grep -c 'field.name == "time" && std::none_of' $f)" = 1 ]

RUN source /opt/ros/noetic/setup.bash && \
    catkin_make
    
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID ros && \
    useradd -m -u $UID -g $GID -s /bin/bash ros

RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc && \
    echo "source /ros_ws/devel/setup.bash" >> ~/.bashrc

CMD ["bash"]
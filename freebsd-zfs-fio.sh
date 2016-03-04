
## root@pve-40-12:~# /root/fio-zfs.sh /tank/migrations/
## Fri Mar  4 11:24:38 CST 2016 fio test on /tank/migrations with --direct=0 --size=4G --iodepth=16 --runtime=30 --group_reporting --numjobs=8 --name=file1 --filename=/tank/migrations/testdir/fio.bin ...
## Fri Mar  4 11:24:38 CST 2016 --- 4k, randread, libaio ...   read : io=162188KB, bw=5403.3KB/s, iops=1350, runt= 30017msec
## Fri Mar  4 11:25:09 CST 2016 --- end
## Fri Mar  4 11:25:10 CST 2016 --- 4k, randread, sync ...   read : io=182032KB, bw=6065.8KB/s, iops=1516, runt= 30010msec
## Fri Mar  4 11:25:40 CST 2016 --- end
## Fri Mar  4 11:25:42 CST 2016 --- 4k, randwrite, libaio ...   write: io=88328KB, bw=2931.8KB/s, iops=732, runt= 30128msec
## Fri Mar  4 11:26:13 CST 2016 --- end
## Fri Mar  4 11:26:14 CST 2016 --- 4k, randwrite, sync ...   write: io=75980KB, bw=2524.6KB/s, iops=631, runt= 30097msec
## Fri Mar  4 11:26:44 CST 2016 --- end
## Fri Mar  4 11:26:47 CST 2016 --- 8M, randread, libaio ...   read : io=6832.0MB, bw=232039KB/s, iops=28, runt= 30150msec
## Fri Mar  4 11:27:18 CST 2016 --- end
## Fri Mar  4 11:27:19 CST 2016 --- 8M, randread, sync ...   read : io=8640.0MB, bw=291905KB/s, iops=35, runt= 30309msec
## Fri Mar  4 11:27:50 CST 2016 --- end
## Fri Mar  4 11:27:52 CST 2016 --- 8M, randwrite, libaio ...   write: io=32768MB, bw=8511.2MB/s, iops=1063, runt=  3850msec
## Fri Mar  4 11:27:56 CST 2016 --- end
## Fri Mar  4 11:27:57 CST 2016 --- 8M, randwrite, sync ...   write: io=32768MB, bw=9492.5MB/s, iops=1186, runt=  3452msec
## Fri Mar  4 11:28:01 CST 2016 --- end
## 
cat <<'EOF'>/root/fio-zfs.sh

#!/bin/sh
#
# fio test
#
#   # fio test
#   
#   sudo mkdir -p /var/lib/vz/tmp && cd /var/lib/vz/tmp
#   sudo wget http://10.236.18.3/x.iso -O x.iso
#   
#   #
#   sudo apt-get -y install fio
#   
#
echo "$1" | grep -q '^-'
if [ $? -ne 0 -a -n "$1" ]
then
    # first arg is not fio opt
    TESTDIR="$1"
    shift
fi

#

if [ -z "$TESTDIR" ]
then
    TESTDIR="$(pwd)"
fi

cd $TESTDIR || exit 1
TESTDIR="$(pwd)"
if [ "$TESTDIR" = "/" ]
then
    echo "error: can not test on root directory."
    exit 1
fi

OPTS="--direct=0 --size=4G --iodepth=16 --runtime=30 --group_reporting --numjobs=8 --name=file1 --filename=${TESTDIR}/testdir/fio.bin"

ADDOPTS="$@"
if [ -n "$ADDOPTS" ]
then
    OPTS="$OPTS $ADDOPTS"
fi

BLOCKS="4k 8M"
ENGS="libaio sync"
RWS="randread randwrite"

echo "`date` fio test on $TESTDIR with $OPTS ..."

mkdir -p ${TESTDIR}/testdir || exit 1

#### mount fs at ${TESTDIR}

# mount /dev/sdd1 ${TESTDIR} -o noatime,ssd,discard,max_inline=12000,noacl,thread_pool=64,compress=lzo

for block in $BLOCKS
do
    for rw in $RWS
    do
        for eng in $ENGS
        do
            fiocmd="fio --rw=$rw --bs=$block --ioengine=$eng $OPTS"
            echo -n "`date` --- $block, $rw, $eng ... "
            $fiocmd | grep ': io=' | grep ', bw='
            exitcode=$?
            #echo "`date` --- $fiocmd"
            echo "`date` ---"
            test $exitcode -ne 0 && break
            sleep 1
        done
        test $exitcode -ne 0 && break
        sleep 1
    done
    test $exitcode -ne 0 && break
    sleep 1
done
test $exitcode -ne 0 && echo "`date` end with error code $exitcode"
#
EOF

chmod +x /root/fio-zfs.sh

/root/fio-zfs.sh /tank/migrations/ --direct=0

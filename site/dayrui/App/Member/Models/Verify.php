<?php namespace Phpcmf\Model\Member;

class Verify extends \Phpcmf\Model
{

    /**
     * 资料审核
     */
    public function save_info($uid, $name, $data) {

        $row = $this->table('member_verify')->where('uid', $uid)->where('tid=1')->getRow();
        $save = [
            'uid' => $uid,
            'tid' => 1,
            'status' => 1,
            'content' => dr_array2string([
                'name' => $name,
                'info' => $data,
            ]),
            'updatetime' => 0,
            'inputtime' => SYS_TIME,
        ];
        if ($row) {
            $this->table('member_verify')->update($row['id'], $save);
            return $row['id'];
        } else {
            $save['result'] = '';
            $rt = $this->table('member_verify')->insert($save);
            return $rt['code'];
        }
    }

    public function info($uid) {

        $row = $this->table('member_verify')->where('uid', $uid)->where('tid=1 and status in (1,0)')->getRow();
        if ($row) {
            $c = dr_string2array($row['content']);
            $row['name'] = $c['name'];
            $row['info'] = $c['info'];
            return $row;
        }

        return [];
    }


    public function save_avatar($uid) {

        $row = $this->table('member_verify')->where('uid', $uid)->where('tid=2')->getRow();
        $save = [
            'uid' => $uid,
            'tid' => 2,
            'status' => 1,
            'content' => '',
            'updatetime' => 0,
            'inputtime' => SYS_TIME,
        ];
        if ($row) {
            $this->table('member_verify')->update($row['id'], $save);
            return $row['id'];
        } else {
            $save['result'] = '';
            $rt = $this->table('member_verify')->insert($save);
            return $rt['code'];
        }
    }

    public function avatar($uid) {

        $row = $this->table('member_verify')->where('uid', $uid)->where('tid=2 and status in (1,0)')->getRow();
        if ($row) {
            return $row;
        }

        return [];
    }
}
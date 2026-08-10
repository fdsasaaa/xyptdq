<?php namespace Phpcmf\Model\Mbdy;

class Code extends \Phpcmf\Model
{

    public function cat_code() {

    }

    public function get_field_code($field, $type, $rt = '', $fname = '', $fixid = 0, $format = 0) {

        $file = dr_get_app_dir('mbdy').'/Models/Field/'.$field['fieldtype'].'.php';
        if (!is_file($file)) {
            if (strpos($field['fieldtype'], ':')) {
                list($a, $b) = explode('::', $field['fieldtype']);
                $file = dr_get_app_dir('mbdy').'/Models/Field/'.$b.'.php';
                if (!is_file($file)) {
                    return '没有找到此字段类型['.$field['fieldtype'].']的调用方式';
                }
            } else {
                return '没有找到此字段类型['.$field['fieldtype'].']的调用方式';
            }
        }

        $id = $rt ? '$'.$rt.'[\'id\']' : '$id';

        if ($fname) {
            $name = $fname;
        } else {
            $name = $rt ? '$'.$rt.'[\''.$field['fieldname'].'\']' : '$'.$field['fieldname'];
            if ($type == 'comment' && $field['fieldname'] == 'inputtime') {
                $time = $rt ? '$'.$rt.'[\''.$field['fieldname'].'\']' : '$'.$field['fieldname'];
            } else {
                $time = $rt ? '$'.$rt.'[\'_'.$field['fieldname'].'\']' : '$_'.$field['fieldname'];
            }
        }

        $fj = '';
        if (in_array($type, ['module', 'form', 'mform']) && $rt && $field['ismain'] == 0) {
            $fj = '<br><br><font color="red">由于本字段属于附表字段，无法在列表或循环中显示，本字段只能在内容页中显示，咨询我QQ提供另类解决方案</font>';
        }

        $name2 = $name;
        $code = str_replace(
            ['{SELF}','MOD_DIR', PHP_EOL, '$value2', '$value', '$id', '$fid', '$time', '$linkname', '$module', '$fixid'],
            [SELF, defined('MOD_DIR') ? MOD_DIR : '', '<br>', $name2, $name, $id, $field['id'], $time, $field['setting']['option']['linkage'], $field['setting']['option']['module'], $fixid],
            file_get_contents($file)
        );

        if ($field['fieldtype'] == 'Ftable') {
            $ftable = '';
            if ($field['setting']['option']['field']) {
                foreach ($field['setting']['option']['field'] as $n => $t) {
                    if ($t['type']) {
                        $val = '{$v['.$n.']}';
                        if ($t['type'] == 3) {
                            // 图片
                            $val = '{dr_get_file($v['.$n.'])}';
                        } elseif ($t['type'] == 4) {
                            // 复选
                            $val = '{php echo $v['.$n.'] ? implode(\'、\', $v['.$n.']) : \'\';}';
                        } elseif ($t['type'] == 7) {
                            // 多行
                            $val = '{php echo nl2br((string)$v[' . $n . ']);}';
                        }
                        $ftable.= $t['name'].': '.$val.'<br>';
                    }
                }
            }
            $code = str_replace('{$ftable}', $ftable, $code);
        } elseif ($field['fieldtype'] == 'Pays') {
            $code = str_replace('$sn', $rt ? '$'.$rt.'[\''.$field['fieldname'].'_sn\']' : '$'.$field['fieldname'].'_sn', $code);
            $code = str_replace('$sku', $rt ? '$'.$rt.'[\''.$field['fieldname'].'_sku\']' : '$'.$field['fieldname'].'_sku', $code);
            $code = str_replace('$image', $rt ? '$'.$rt.'[\''.$field['fieldname'].'_image\']' : '$'.$field['fieldname'].'_image', $code);
            $code = str_replace('$quantity', $rt ? '$'.$rt.'[\''.$field['fieldname'].'_quantity\']' : '$'.$field['fieldname'].'_quantity', $code);
        }
        if (!$rt && in_array($field['fieldtype'], ['Tags', 'Kws'])) {
            // 内容页不需要函数处理
            $arr = explode('<br>', $code);
            unset($arr[0]);
            $code = implode('<br>', $arr);
        }

        return $code.$fj;

    }

    public function get_linkage_field_code($field, $mid, $id) {

        $html = '';

        $html.= '{php $mylink=dr_linkage(\''.$mid.'\','.$id.');}<br>'.PHP_EOL;

        $html.= $this->get_field_code($field, 0, $rt = 'mylink');

        return $html;
    }

    public function get_category_field_code($field, $mid, $id) {

        if ($mid == 'share' || !$mid) {
            //$html = '{php $mycat=dr_share_cat_value('.$id.', \''.$field['fieldname'].'\');} 这句话必须要,配合下面的标签进行输出'.PHP_EOL;
            $fname = 'dr_share_cat_value('.$id.', \''.$field['fieldname'].'\')';
        } else {
            //$html = '{php $mycat=dr_cat_value(\''.$mid.'\','.$id.', \''.$field['fieldname'].'\');} 这句话必须要,配合下面的标签进行输出'.PHP_EOL;
            $fname = 'dr_cat_value(\''.$mid.'\','.$id.', \''.$field['fieldname'].'\')';
        }


        $html = htmlspecialchars('<?php $mycat='.$fname.';?>');
        $html.= '（这句话很重要，一定不可少）'.PHP_EOL.'<hr>';

        $fname = '$mycat';

        $html.= $this->get_field_code($field, 0, '', $fname, $id);

        return $html;
    }

    public function get_site_field_code($field) {

        $html = htmlspecialchars('<?php $mysite=dr_site_value(\''.$field['fieldname'].'\');?>');
        $html.= '（这句话很重要，一定不可少）'.PHP_EOL.'<hr>';
        $fname = '$mysite';

        $html.= $this->get_field_code($field, 0, '', $fname);

        return $html;
    }

    public function get_category_list_code($field, $mid, $return) {

        if ($mid == 'share' || !$mid) {
            //$html = '{php $mycat=dr_share_cat_value($'.$return.'.catid, \''.$field['fieldname'].'\');} 这句话必须要,配合下面的标签进行输出'.PHP_EOL;
            $fname = 'dr_share_cat_value($'.$return.'.catid, \''.$field['fieldname'].'\')';
        } else {
            //$html = '{php $mycat=dr_cat_value(\''.$mid.'\', $'.$return.'.catid, \''.$field['fieldname'].'\');} 这句话必须要,配合下面的标签进行输出'.PHP_EOL;
            $fname = 'dr_cat_value(\''.$mid.'\', $'.$return.'.catid, \''.$field['fieldname'].'\')';
        }

        $html = htmlspecialchars('<?php $mycat='.$fname.';?>');
        $html.= '（这句话很重要，一定不可少）'.PHP_EOL.'<hr>';

        $fname = '$mycat';
        $html.= $this->get_field_code($field, 0, '', $fname);

        return $html;
    }


}
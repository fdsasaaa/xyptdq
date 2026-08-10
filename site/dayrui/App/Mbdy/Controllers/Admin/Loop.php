<?php namespace Phpcmf\Controllers\Admin;

class Loop extends \Phpcmf\App
{

    public function index() {
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '循环标签调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'list' => [
                [
                    'name' => '栏目循环',
                    'uri' => 'mbdy/categoryshow/index',
                    'msg' => '调用栏目分类列表，比如顶级栏目列表，某个子栏目列表等等',
                ],
                [
                    'name' => '模块内容循环',
                    'uri' => 'mbdy/loop/module',
                    'msg' => '调用内容列表的N条数据，比如最新N条数据，某栏目N条数据等等',
                ],
                [
                    'name' => '网站表单内容循环',
                    'uri' => 'mbdy/loop/form',
                    'msg' => '调用网站表单内容的列表的N条数据，比如最新N条数据，全部表单数据等等',
                ],
                [
                    'name' => '模块表单内容循环',
                    'uri' => 'mbdy/loop/mform',
                    'msg' => '调用模块表单内容的列表的N条数据，比如最新N条数据，某条内容的表单记录，全部模块表单数据等等',
                ],
            ],
        ]);
        \Phpcmf\Service::V()->display('index.html');
    }


    public function module() {

        if (IS_POST) {

            $data = \Phpcmf\Service::L('input')->post('data');
            if (!$data['module']) {
                $this->_json(0, '必须选择模块');
            }

            $code = '{module module='.$data['module'];

            if ($data['id']) {
                if (strpos($data['id'], ',') !== false) {
                    $code.= ' IN_id='.$data['id'];
                } else {
                    $code.= ' id='.$data['id'];
                }
            }
            if ($data['catid']) {
                $code.= ' catid='.$data['catid'];
            }
            if ($data['num']) {
                $code.= ' num='.$data['num'];
            }

            if ($data['flag']) {
                $code.= ' flag='.$data['flag'];
            }

            if ($data['lmmx']) {
                $code.= ' more=1';
            }

            if ($data['fb']) {
                $code.= ' join='.SITE_ID.'_'.$data['module'].'_data_0 on=id';
            }

            if ($data['order']) {
                $code.= ' order='.$data['order'];
                if ($data['order_by']) {
                    $code.= '_asc';
                }
            }



            if (!$data['return']) {
                $data['return'] = 't';
            }
            if ($data['return'] != 't') {
                $code.= ' return='.$data['return'].'}<br>';
            } else {
                $code.= '}<br>';
            }

            if ($data['return'] != 't') {
                $code .= '<br>当前行数(从1开始)：{$key_'.$data['return'].'+1}';
                $code .= '<br>当前行数(从0开始)：{$key_'.$data['return'].'}';
            } else {
                $code .= '<br>当前行数(从1开始)：{$key+1}';
                $code .= '<br>当前行数(从0开始)：{$key}';
            }
            $code.= '<br>判断是否第一条，{if $is_first}第一条{/if}';
            $code.= '<br>判断是否最后一条，{if $is_last}最后一条{/if}';
            $code.= '<br><br>';
            $code.= '循环体内的字段标签，请在右边生成：====>>>>>> ====>>>>>> ====>>>>>>';
            $code.= '<br><br>';
            $code.= '<br>{/module}<br>';

            if ($data['return'] != 't') {
                $code.= '<br>诊断信息：{$debug_'.$data['return'].'}';
                $code.= '<br>本次记录数：{$count_'.$data['return'].'}';
            } else {
                $code.= '<br>诊断信息：{$debug}';
                $code.= '<br>本次记录数：{$count}';
            }


            $field = '<select class="form-control" name="field">';
            $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$data['module']);
            $fields = $this->_module_field($mdata['field'], $mdata['category_data_field']);
            foreach ($fields as $t) {
                $field.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
            }
            $field.= '</select>';

            $this->_json(1, $code, [
                'mid' => $data['module'],
                'return' => $data['return'],
                'field' => $field,
            ]);
            exit;
        }

        \Phpcmf\Service::V()->assign('mid', dr_safe_filename($_GET['mid']));
        \Phpcmf\Service::V()->assign('catid', intval($_GET['catid']));
        \Phpcmf\Service::V()->display('loop_module.html');
    }

    private function _module_field($field, $f2) {
        // 默认字段
        $field['inputtime'] = [
            'name' => dr_lang('录入时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
        ];
        $field['updatetime'] = [
            'name' => dr_lang('更新时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'updatetime',
        ];
        $field['catid'] = [
            'name' => dr_lang('栏目信息'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Catid',
            'fieldname' => 'catid',
        ];
        $field['uid'] = [
            'name' => dr_lang('账号'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Uid',
            'fieldname' => 'uid',
        ];
        $field['url'] = [
            'name' => dr_lang('内容地址'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'url',
        ];
        $field['hits'] = [
            'name' => dr_lang('浏览次数'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'hits',
        ];
        return $field + $f2;
    }



    public function form() {

        if (IS_POST) {

            $data = \Phpcmf\Service::L('input')->post('data');
            if (!$data['module']) {
                $this->_json(0, '必须选择表单');
            }

            $code = '{form form='.$data['module'];

            if ($data['id']) {
                if (strpos($data['id'], ',') !== false) {
                    $code.= ' IN_id='.$data['id'];
                } else {
                    $code.= ' id='.$data['id'];
                }
            }
            if ($data['num']) {
                $code.= ' num='.$data['num'];
            }

            if ($data['order']) {
                $code.= ' order='.$data['order'];
                if ($data['order_by']) {
                    $code.= '_asc';
                }
            }


            if (!$data['return']) {
                $data['return'] = 't';
            }
            if ($data['return'] != 't') {
                $code.= ' return='.$data['return'].'}<br>';
            } else {
                $code.= '}<br>';
            }

            if ($data['return'] != 't') {
                $code .= '<br>当前行数(从1开始)：{$key_'.$data['return'].'+1}';
                $code .= '<br>当前行数(从0开始)：{$key_'.$data['return'].'}';
            } else {
                $code .= '<br>当前行数(从1开始)：{$key+1}';
                $code .= '<br>当前行数(从0开始)：{$key}';
            }
            $code.= '<br>判断是否第一条，{if $is_first}第一条{/if}';
            $code.= '<br>判断是否最后一条，{if $is_last}最后一条{/if}';
            $code.= '<br><br>';
            $code.= '循环体内的字段标签，请在右边生成：====>>>>>> ====>>>>>> ====>>>>>>';
            $code.= '<br><br>';
            $code.= '<br>{/form}<br>';

            if ($data['return'] != 't') {
                $code.= '<br>诊断信息：{$debug_'.$data['return'].'}';
                $code.= '<br>本次记录数：{$count_'.$data['return'].'}';
            } else {
                $code.= '<br>诊断信息：{$debug}';
                $code.= '<br>本次记录数：{$count}';
            }


            $field = '<select class="form-control" name="field">';
            $mdata = \Phpcmf\Service::L('cache')->get('form-'.SITE_ID, $data['module']);
            $fields = $this->_form_field($mdata['field']);
            foreach ($fields as $t) {
                $field.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
            }
            $field.= '</select>';

            $this->_json(1, $code, [
                'mid' => $data['module'],
                'return' => $data['return'],
                'field' => $field,
            ]);
            exit;
        }

        \Phpcmf\Service::V()->display('loop_form.html');
    }

    private function _form_field($field) {
        // 默认字段
        $field['inputtime'] = [
            'name' => dr_lang('录入时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
        ];
        return $field;
    }


    public function mform() {

        if (IS_POST) {

            $data = \Phpcmf\Service::L('input')->post('data');
            if (!$data['module']) {
                $this->_json(0, '必须选择模块');
            }

            list($mid, $b, $fid) = explode('_', $data['module']);

            $code = '{mform module='.$mid .' form='.$fid;
            if ($data['id']) {
                if (strpos($data['id'], ',') !== false) {
                    $code.= ' IN_id='.$data['id'];
                } else {
                    $code.= ' id='.$data['id'];
                }
            }
            if ($data['num']) {
                $code.= ' num='.$data['num'];
            }

            if ($data['cid']) {
                $code.= ' cid='.$data['cid'];
            }

            if ($data['order']) {
                $code.= ' order='.$data['order'];
                if ($data['order_by']) {
                    $code.= '_asc';
                }
            }



            if (!$data['return']) {
                $data['return'] = 't';
            }
            if ($data['return'] != 't') {
                $code.= ' return='.$data['return'].'}<br>';
            } else {
                $code.= '}<br>';
            }

            if ($data['return'] != 't') {
                $code .= '<br>当前行数(从1开始)：{$key_'.$data['return'].'+1}';
                $code .= '<br>当前行数(从0开始)：{$key_'.$data['return'].'}';
            } else {
                $code .= '<br>当前行数(从1开始)：{$key+1}';
                $code .= '<br>当前行数(从0开始)：{$key}';
            }
            $code.= '<br>判断是否第一条，{if $is_first}第一条{/if}';
            $code.= '<br>判断是否最后一条，{if $is_last}最后一条{/if}';
            $code.= '<br><br>';
            $code.= '循环体内的字段标签，请在右边生成：====>>>>>> ====>>>>>> ====>>>>>>';
            $code.= '<br><br>';
            $code.= '<br>{/mform}<br>';

            if ($data['return'] != 't') {
                $code.= '<br>诊断信息：{$debug_'.$data['return'].'}';
                $code.= '<br>本次记录数：{$count_'.$data['return'].'}';
            } else {
                $code.= '<br>诊断信息：{$debug}';
                $code.= '<br>本次记录数：{$count}';
            }


            $field = '<select class="form-control" name="field">';
            $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$mid, 'form', $fid);
            $fields = $this->_mform_field($mdata['field']);
            foreach ($fields as $t) {
                $field.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
            }
            $field.= '</select>';

            $this->_json(1, $code, [
                'mid' => $mid,
                'fid' => $fid,
                'return' => $data['return'],
                'field' => $field,
            ]);
            exit;
        }

        $mform = [];
        $module = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-content');
        if (!$module) {
            $this->_admin_msg(0, dr_lang('系统没有安装内容模块'));
        }

        foreach ($module as $m) {
            $mform[] = [
                'name' => $m['name']
            ];

            $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$m['dirname'], 'form');
            if ($mdata) {
                foreach ($mdata as $t) {
                    $mform[] = [
                        'mid' => $m['dirname'].'_form_'.$t['table'],
                        'name' => $t['name'],
                        'table' => $t['table'],
                    ];
                }
            } else {
                $mform[] = [
                    'mid' => $m['dirname'].'_form_没有创建模块表单',
                    'name' =>'没有创建模块表单',
                    'table' => '',
                ];
            }

        }

        \Phpcmf\Service::V()->assign('mform', $mform);
        \Phpcmf\Service::V()->display('loop_mform.html');
    }

    private function _mform_field($field) {
        // 默认字段
        $field['inputtime'] = [
            'name' => dr_lang('录入时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
        ];
        $field['updatetime'] = [
            'name' => dr_lang('更新时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'updatetime',
        ];
        $field['catid'] = [
            'name' => dr_lang('栏目信息'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Catid',
            'fieldname' => 'catid',
        ];
        $field['uid'] = [
            'name' => dr_lang('账号'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Uid',
            'fieldname' => 'uid',
        ];

        return $field;
    }


}

<?php namespace Phpcmf\Controllers\Admin;


class Seo extends \Phpcmf\Common {

    public function index() {

        if (IS_AJAX_POST) {
            $rt = \Phpcmf\Service::M('Site')->config(
                SITE_ID,
                'seo',
                \Phpcmf\Service::L('input')->post('data', true)
            );
            \Phpcmf\Service::M('Site')->config_value(SITE_ID, 'config', [
                'SITE_INDEX_HTML' => intval(\Phpcmf\Service::L('input')->post('SITE_INDEX_HTML'))
            ]);
            if (!is_array($rt)) {
                $this->_json(0, dr_lang('网站SEO(#%s)不存在', SITE_ID));
            }
            \Phpcmf\Service::L('input')->system_log('设置网站SEO');
            \Phpcmf\Service::M('cache')->sync_cache('');
            $this->_json(1, dr_lang('操作成功'));
        }

        $page = intval(\Phpcmf\Service::L('input')->get('page'));
        $data = \Phpcmf\Service::M('Site')->config(SITE_ID);

        \Phpcmf\Service::V()->assign([
            'page' => $page,
            'data' => $data['seo'],
            'form' => dr_form_hidden(['page' => $page]),
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '站点SEO' => [APP_DIR.'/seo/index', 'fa fa-cog'],
                    'help' => [494],
                ]
            ),
            'module' => \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-content'),
            'site_name' => $this->site_info[SITE_ID]['SITE_NAME'],
            'SITE_INDEX_HTML' => $data['config']['SITE_INDEX_HTML'],
        ]);
        \Phpcmf\Service::V()->display('seo.html');
    }

    public function sync_index() {

        $url = dr_url(APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/'.\Phpcmf\Service::L('Router')->method);
        $page = intval(\Phpcmf\Service::L('input')->get('page'));
        if (!$page) {
            // 计算数量
            $total = \Phpcmf\Service::M()->db->table('module')->countAllResults();
            if (!$total) {
                $this->_html_msg(0, dr_lang('无可用模块更新'));
            }
            $this->_html_msg(1, dr_lang('正在执行中...'), $url.'&total='.$total.'&page=1');
        }

        $psize = 100; // 每页处理的数量
        $total = (int)\Phpcmf\Service::L('input')->get('total');
        $tpage = ceil($total / $psize); // 总页数

        // 更新完成
        if ($page > $tpage) {
            \Phpcmf\Service::M('cache')->sync_cache('');
            $this->_html_msg(1, dr_lang('更新完成'));
        }

        $category = \Phpcmf\Service::M()->db->table('module')->limit($psize, $psize * ($page - 1))->orderBy('id DESC')->get()->getResultArray();
        if ($category) {
            $site = \Phpcmf\Service::M('Site')->config(SITE_ID);
            $update = [];
            foreach ($category as $data) {
                $data['site'] = dr_string2array($data['site']);
                $data['site'][SITE_ID]['show_title'] = $site['seo']['show_title'];
                $data['site'][SITE_ID]['show_keywords'] = $site['seo']['show_keywords'];
                $data['site'][SITE_ID]['show_description'] = $site['seo']['show_description'];
                $update[] = [
                    'id' => (int)$data['id'],
                    'site'=> dr_array2string($data['site']),
                ];
            }
            $update && \Phpcmf\Service::M()->table('module')->update_batch($update);
        }

        $this->_html_msg(1, dr_lang('正在执行中【%s】...', "$tpage/$page"), $url.'&total='.$total.'&page='.($page+1));
    }

}

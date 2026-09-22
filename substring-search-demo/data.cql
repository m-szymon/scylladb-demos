-- Substring search demo: seventeen accounts.
-- The nicknames are chosen so that containment, character order and case each make a visible
-- difference: 将军 (general) is inside five nicknames, 南宫 is a family name but 宫南 is not,
-- NG appears in nicknames and usernames in both cases, and 925555 is a prefix of 9255551.

INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (ac195af8-6535-476f-b876-fb1cc9a96946, 0, '宇将军',       '2024-01-01T00:00:00+0000', 0, 'user0001');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (e236ee35-83ee-4a12-b3cf-5205bda686c1, 0, '李将军',       '2024-02-01T00:00:00+0000', 0, 'user0002');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (2f10c77a-e76a-49f7-8f5c-4646923476e6, 0, '将军来了',     '2024-03-01T00:00:00+0000', 0, 'jiangjunlaile');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (2c983f0a-960f-47df-b7d1-bafc4a0d2784, 0, '将领',         '2024-01-05T00:00:00+0000', 0, 'user0004');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (2cfbb005-a436-44e4-aae1-7ba1d5c9427d, 0, '元帅',         '2024-01-06T00:00:00+0000', 0, 'user0005');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (b2203663-516f-4118-a6fb-dc696a9cca73, 0, '司令',         '2024-01-07T00:00:00+0000', 0, 'user0006');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (aa409a60-e1c1-461e-b247-1eb359164c2c, 0, '南宫月',       '2024-04-01T00:00:00+0000', 0, 'user0007');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (b8cc22c4-06f7-4762-b3d8-81074c53c79c, 0, '小南宫粉丝团', '2024-04-15T00:00:00+0000', 0, 'user0008');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (1c471a52-3f6b-4143-8e71-f49e0c6f86ea, 0, '宫南',         '2024-01-08T00:00:00+0000', 0, 'user0009');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (27d85c1c-7d35-424c-834d-75b1d80d6f02, 0, 'NG玩家',       '2024-05-01T00:00:00+0000', 0, 'NGgamer');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (925e33ec-117c-4e98-aa72-8e17823adb9b, 0, '国王NG',       '2024-05-02T00:00:00+0000', 0, 'kingNG');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (5e52c195-759f-4a03-98cf-5f9160c6fd03, 0, 'GN小号',       '2024-01-09T00:00:00+0000', 0, 'gn');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (97e73aac-e35c-4236-81cd-c50ae626bfd2, 0, '小明',         '2024-06-01T00:00:00+0000', 0, '925555');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (cd4c5b34-35e4-4e2a-9b56-80ab580154d0, 0, '小红',         '2024-06-02T00:00:00+0000', 0, '9255551');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (be7e4d7d-784e-489f-bc2d-7ed626d1fcc7, 0, '小刚',         '2024-01-10T00:00:00+0000', 0, '925');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (7bd0df74-f528-47b7-921e-fb8a45a30208, 0, '王将军',       '2024-07-01T00:00:00+0000', 0, 'user0016');
INSERT INTO search_demo.users (user_id, account_type, nickname, register_time, status, username) VALUES (2a8083ad-308e-42ac-9681-b0f21282e7da, 0, '被禁将军',     '2024-07-02T00:00:00+0000', 1, 'user0017');
